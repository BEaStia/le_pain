# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'securerandom'
require_relative 'circuit_breaker'
require_relative 'retry_policy'

module LePain
  module HttpAdapters
    class NetHttpAdapter
      def execute(request, timeout:, follow_redirects: true)
        uri = request.uri
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = timeout
        http.read_timeout = timeout

        response = http.request(request)
        return follow_redirect(request, response, timeout, follow_redirects) if redirect?(response) && follow_redirects

        response
      end

      private

      def redirect?(response)
        response.is_a?(Net::HTTPRedirection) && response['location']
      end

      def follow_redirect(request, response, timeout, follow_redirects)
        redirected = request.class.new(URI(response['location']))
        request.each_header { |key, value| redirected[key] = value }
        redirected.body = request.body if request.request_body_permitted?
        execute(redirected, timeout: timeout, follow_redirects: follow_redirects)
      end
    end

    class StubAdapter
      Response = Struct.new(:code, :body, :headers, keyword_init: true) do
        def to_hash
          headers.to_h.transform_values { |value| Array(value) }
        end
      end

      attr_reader :requests

      def initialize(responses: {}, &handler)
        @responses = responses
        @handler = handler
        @requests = []
      end

      def execute(request, timeout:, follow_redirects: true)
        @requests << request
        response = @handler ? @handler.call(request) : response_for(request)
        normalize_response(response)
      end

      private

      def response_for(request)
        key = "#{request.method} #{request.uri.path}"
        configured = @responses[key] || @responses[request.uri.path] || @responses[:default]
        configured = configured.shift if configured.is_a?(Array)
        configured || { status: 404, body: { error: 'not found' } }
      end

      def normalize_response(response)
        return response if response.respond_to?(:code) && response.respond_to?(:to_hash)

        status = response[:status] || response['status'] || 200
        body = response[:body] || response['body'] || {}
        headers = response[:headers] || response['headers'] || {}
        Response.new(
          code: status.to_s,
          body: body.is_a?(String) ? body : JSON.generate(body),
          headers: headers
        )
      end
    end
  end

  class HttpClient
    TRANSIENT_STATUSES = [408, 429, 500, 502, 503, 504].freeze
    TRANSIENT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Timeout::Error].freeze

    attr_reader :base_url, :default_headers, :timeout, :max_retries, :adapter, :follow_redirects, :circuit_breaker, :retry_base_delay

    class << self
      def adapters
        @adapters ||= {
          net_http: HttpAdapters::NetHttpAdapter,
          stub: HttpAdapters::StubAdapter,
        }
      end

      def register_adapter(name, adapter_class)
        adapters[name.to_sym] = adapter_class
      end

      def adapter(name)
        adapters.fetch(name.to_sym) { raise ConfigurationError, "unknown HTTP adapter: #{name}" }
      end

      def for(service_name, config: Application.config)
        http_config = config['http_client'] || {}
        service_config = http_config.dig('services', service_name.to_s) ||
                         http_config.dig('services', service_name.to_s.tr('_', '-')) ||
                         {}
        raise ConfigurationError, "unknown HTTP service: #{service_name}" unless service_config['base_url']

        new(
          base_url: service_config['base_url'],
          default_headers: service_config['headers'] || {},
          timeout: service_config['timeout'] || http_config['default_timeout'] || 5,
          max_retries: service_config['retries'] || http_config['max_retries'] || 0,
          follow_redirects: service_config.fetch('follow_redirects', http_config.fetch('follow_redirects', true)),
          adapter: service_config['adapter'] || http_config['adapter'] || :net_http,
          circuit_breaker: service_config['circuit_breaker'] || http_config['circuit_breaker'],
          retry_base_delay: service_config['retry_base_delay'] || http_config['retry_base_delay'] || 0.5
        )
      end
    end

    def initialize(base_url:, default_headers: {}, timeout: 5, max_retries: 0, follow_redirects: true, adapter: :net_http, circuit_breaker: nil, logger: nil, retry_base_delay: 0.5)
      @base_url = base_url.chomp('/')
      @default_headers = default_headers
      @timeout = timeout
      @max_retries = max_retries.to_i
      @follow_redirects = follow_redirects
      @adapter = build_adapter(adapter)
      @circuit_breaker = build_circuit_breaker(circuit_breaker)
      @logger = logger
      @retry_base_delay = retry_base_delay
    end

    def get(path, headers: {}, query: {})
      uri = build_uri(path, query)
      request = Net::HTTP::Get.new(uri)
      inject_headers(request, headers)
      execute(request)
    end

    def post(path, body: {}, headers: {})
      uri = URI("#{base_url}#{path}")
      request = Net::HTTP::Post.new(uri)
      inject_headers(request, headers)
      inject_idempotency_key(request)
      request['Content-Type'] = 'application/json' unless request['Content-Type']
      request.body = body.is_a?(String) ? body : JSON.generate(body)
      execute(request)
    end

    def put(path, body: {}, headers: {})
      uri = URI("#{base_url}#{path}")
      request = Net::HTTP::Put.new(uri)
      inject_headers(request, headers)
      inject_idempotency_key(request)
      request['Content-Type'] = 'application/json' unless request['Content-Type']
      request.body = body.is_a?(String) ? body : JSON.generate(body)
      execute(request)
    end

    def delete(path, headers: {})
      uri = URI("#{base_url}#{path}")
      request = Net::HTTP::Delete.new(uri)
      inject_headers(request, headers)
      inject_idempotency_key(request)
      execute(request)
    end

    private

    def build_adapter(adapter)
      return adapter unless adapter.is_a?(Symbol) || adapter.is_a?(String)

      self.class.adapter(adapter).new
    end

    def build_circuit_breaker(config)
      case config
      when CircuitBreaker
        config
      when Hash
        CircuitBreaker.new(
          name: config[:name] || config['name'] || "http_client:#{base_url}",
          failure_threshold: config[:failure_threshold] || config['failure_threshold'] || 5,
          success_threshold: config[:success_threshold] || config['success_threshold'] || 2,
          timeout: config[:timeout] || config['timeout'] || 30
        )
      when true
        CircuitBreaker.new(name: "http_client:#{base_url}")
      end
    end

    def build_uri(path, query)
      uri = URI("#{base_url}#{path}")
      uri.query = URI.encode_www_form(query) if query.any?
      uri
    end

    def inject_headers(request, extra_headers)
      context = Context.current

      request['x-request-id'] = context.request_id if context
      request['x-trace-id'] = context.trace_id if context
      request['x-correlation-id'] = context.correlation_id if context
      request['authorization'] = context.auth if context&.auth
      request['idempotency-key'] = context.idempotency_key if context&.idempotency_key

      default_headers.each { |k, v| request[k] ||= v }
      extra_headers.each { |k, v| request[k] = v }
    end

    def inject_idempotency_key(request)
      return if request['idempotency-key']
      return unless max_retries.positive?

      request['idempotency-key'] = SecureRandom.uuid
    end

    def execute(request)
      attempts = 0
      loop do
        attempts += 1
        log_request(request, attempts)

        response = with_circuit_breaker do
          HttpResponse.new(adapter.execute(request, timeout: timeout, follow_redirects: follow_redirects))
        end
        log_response(request, response, attempts)

        return response unless retryable_response?(response) && attempts <= max_retries

        sleep(retry_delay(attempts))
      rescue *TRANSIENT_ERRORS => e
        log_error(request, e, attempts)
        raise if attempts > max_retries

        sleep(retry_delay(attempts))
      end
    end

    def with_circuit_breaker(&block)
      circuit_breaker ? circuit_breaker.call(&block) : yield
    end

    def retryable_response?(response)
      TRANSIENT_STATUSES.include?(response.status)
    end

    def retry_delay(attempt)
      RetryPolicy.new(max_attempts: max_retries + 1, base_delay: retry_base_delay, jitter: false).calculate_delay(attempt)
    end

    def log_request(request, attempt)
      logger&.info(
        'http client request',
        extra: {
          method: request.method,
          url: request.uri.to_s,
          attempt: attempt,
        }
      )
    end

    def log_response(request, response, attempt)
      logger&.info(
        'http client response',
        extra: {
          method: request.method,
          url: request.uri.to_s,
          status: response.status,
          attempt: attempt,
        }
      )
    end

    def log_error(request, error, attempt)
      logger&.warn(
        'http client error',
        extra: {
          method: request.method,
          url: request.uri.to_s,
          error: error.message,
          attempt: attempt,
        }
      )
    end

    def logger
      @logger || Application.logger
    end
  end

  class HttpResponse
    attr_reader :status, :body, :headers, :raw

    def initialize(net_response)
      @raw = net_response
      @status = net_response.code.to_i
      @headers = net_response.to_hash.transform_values { |v| v.first }
      @body = parse_body(net_response.body)
    end

    def success?
      (200...300).cover?(@status)
    end

    def [](key)
      @body[key]
    end

    def header(name)
      @headers[name.downcase]
    end

    private

    def parse_body(raw_body)
      return {} if raw_body.nil? || raw_body.empty?

      JSON.parse(raw_body)
    rescue JSON::ParserError
      { raw: raw_body }
    end
  end
end
