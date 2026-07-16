# frozen_string_literal: true

module LePain
  module Middleware
    class << self
      def resolve(name)
        case name.to_s
        when 'request_id' then RequestId
        when 'cors' then Cors
        when 'compression' then Compression
        when 'timeout' then Timeout
        when 'rate_limit' then RateLimit
        when 'security_headers' then Security::SecurityHeaders
        when 'security_payload_limit' then Security::PayloadLimit
        when 'security_input_sanitizer' then Security::InputSanitizer
        when 'security_audit_log' then Security::AuditLog
        else
          raise ArgumentError, "Unknown middleware: #{name}"
        end
      end
    end

    class Pipeline
      attr_reader :middlewares

      def initialize
        @middlewares = []
      end

      def register(name, middleware_class, only: nil, except: nil, condition: nil, **options)
        @middlewares << build_entry(name, middleware_class, only: only, except: except, condition: condition, **options)
      end

      def insert_before(target_name, name, middleware_class, only: nil, except: nil, condition: nil, **options)
        idx = @middlewares.index { |m| m[:name] == target_name }
        raise ArgumentError, "Middleware '#{target_name}' not found" unless idx

        @middlewares.insert(idx, build_entry(name, middleware_class, only: only, except: except, condition: condition, **options))
      end

      def insert_after(target_name, name, middleware_class, only: nil, except: nil, condition: nil, **options)
        idx = @middlewares.index { |m| m[:name] == target_name }
        raise ArgumentError, "Middleware '#{target_name}' not found" unless idx

        @middlewares.insert(idx + 1, build_entry(name, middleware_class, only: only, except: except, condition: condition, **options))
      end

      def remove(name)
        @middlewares.reject! { |m| m[:name] == name }
      end

      def execute(request, context, &handler)
        chain = @middlewares.reverse.reduce(handler) do |next_handler, middleware_entry|
          lambda do |req, ctx|
            if applies?(middleware_entry, req, ctx)
              middleware_entry[:instance].call(req, ctx, next_handler)
            else
              next_handler.call(req, ctx)
            end
          end
        end

        chain.call(request, context)
      end

      def names
        @middlewares.map { |m| m[:name] }
      end

      def clear
        @middlewares.clear
      end

      private

      def build_entry(name, middleware_class, only:, except:, condition:, **options)
        {
          name: name,
          instance: middleware_class.new(**options),
          only: only,
          except: except,
          condition: condition,
        }
      end

      def applies?(entry, request, context)
        matches = condition_matches?(entry[:only], request, context)
        excluded = entry[:except] && condition_matches?(entry[:except], request, context)
        custom = entry[:condition]

        matches && !excluded && (!custom || custom.call(request, context))
      end

      def condition_matches?(condition, request, context)
        return true unless condition

        condition.all? do |key, expected|
          case key.to_sym
          when :path, :action
            path_matches?(expected, request.action)
          when :transport
            Array(expected).map(&:to_sym).include?(request.transport.to_sym)
          when :context
            expected.respond_to?(:call) ? expected.call(context) : false
          else
            context.metadata[key.to_s] == expected || request.meta(key) == expected
          end
        end
      end

      def path_matches?(condition, action)
        path = action.to_s.include?(':') ? action.to_s.split(':', 2).last : action.to_s

        case condition
        when Regexp
          condition.match?(action) || condition.match?(path)
        else
          pattern = condition.to_s
          return true if pattern == action || pattern == path

          regex = pattern.gsub(/:([^\/]+)/, '[^/]+')
          /\A#{regex}\z/.match?(path) || /\A#{regex}\z/.match?(action)
        end
      end
    end

    class Base
      def initialize(**options)
        @options = options
      end

      def call(request, context, next_handler)
        raise NotImplementedError
      end
    end

    class RequestId
      def initialize(**options)
        @header = options.fetch(:header, 'x-request-id')
      end

      def call(request, context, next_handler)
        unless request.headers[@header]
          request.headers[@header] = context.request_id
        end
        response = next_handler.call(request, context)
        response.headers[@header] ||= context.request_id
        response
      end
    end

    class Cors
      def initialize(**options)
        @allowed_origins = options.fetch(:allowed_origins, ['*'])
        @allowed_methods = options.fetch(:allowed_methods, %w[GET POST PUT DELETE PATCH])
        @allowed_headers = options.fetch(:allowed_headers, ['Content-Type', 'Authorization'])
        @max_age = options.fetch(:max_age, 86400)
      end

      def call(request, context, next_handler)
        response = next_handler.call(request, context)
        origin = request.headers['origin'] || '*'

        allowed = @allowed_origins.include?('*') || @allowed_origins.include?(origin)
        if allowed
          response.headers['Access-Control-Allow-Origin'] = origin
          response.headers['Access-Control-Allow-Methods'] = @allowed_methods.join(', ')
          response.headers['Access-Control-Allow-Headers'] = @allowed_headers.join(', ')
          response.headers['Access-Control-Max-Age'] = @max_age.to_s
        end

        response
      end
    end

    class Timeout
      def initialize(**options)
        @timeout = options.fetch(:timeout, 30)
      end

      def call(request, context, next_handler)
        Timeout.timeout(@timeout) do
          next_handler.call(request, context)
        end
      rescue ::Timeout::Error
        LePain::Response.error('Request timeout', status: 408)
      end
    end

    class Compression
      def initialize(**options)
        @enabled = options.fetch(:enabled, true)
        @algorithms = Array(options.fetch(:algorithms, %w[gzip br])).map(&:to_s)
        @min_size = options.fetch(:min_size, 1024)
        @content_types = Array(options.fetch(:content_types, [
          'application/json',
          'text/plain',
          'application/xml',
        ]))
        @metrics = options.fetch(:metrics, true)
      end

      def call(request, context, next_handler)
        return next_handler.call(request, context) unless @enabled

        decompression_error = decompress_request(request)
        return decompression_error if decompression_error

        response = next_handler.call(request, context)
        compress_response(request, response)
      end

      private

      def decompress_request(request)
        encoding = header(request.headers, 'content-encoding')
        return nil if encoding.nil? || encoding.empty? || encoding == 'identity'

        return unsupported_encoding(encoding) unless @algorithms.include?(encoding) && supported_algorithm?(encoding)

        compressed = request.raw || request.payload
        decompressed = decompress(compressed, encoding)
        payload = parse_payload(decompressed)

        request.instance_variable_set(:@payload, payload)
        request.headers.delete('content-encoding')
        request.headers.delete('Content-Encoding')
        request.headers.delete('content-length')
        request.headers.delete('Content-Length')
        nil
      rescue StandardError => e
        LePain::Response.bad_request("Failed to decompress request: #{e.message}")
      end

      def unsupported_encoding(encoding)
        response = LePain::Response.error("Unsupported content encoding: #{encoding}", status: 415, code: 'unsupported_encoding')
        response.headers['Accept-Encoding'] = @algorithms.select { |algo| supported_algorithm?(algo) }.join(', ')
        response
      end

      def compress_response(request, response)
        return response if header(response.headers, 'content-encoding')

        body = response.to_json
        return response if body.bytesize < @min_size
        return response unless compressible_content_type?(response)

        algorithm = negotiate_algorithm(request)
        return response unless algorithm

        start = monotonic_time
        compressed = compress(body, algorithm)
        duration = monotonic_time - start

        response.headers['Content-Encoding'] = algorithm
        response.headers['Content-Length'] = compressed.bytesize.to_s
        response.headers['Vary'] = append_vary(response.headers['Vary'], 'Accept-Encoding')
        response.instance_variable_set(:@compressed_body, compressed)
        track_metrics(algorithm, body.bytesize, compressed.bytesize, duration)

        response
      end

      def negotiate_algorithm(request)
        accepted = parse_accept_encoding(header(request.headers, 'accept-encoding'))
        @algorithms.find do |algorithm|
          supported_algorithm?(algorithm) && accepted.fetch(algorithm, accepted.fetch('*', 0.0)).positive?
        end
      end

      def parse_accept_encoding(value)
        return {} if value.nil? || value.empty?

        value.split(',').each_with_object({}) do |entry, accepted|
          encoding, *params = entry.strip.split(';')
          quality = params.find { |param| param.strip.start_with?('q=') }
          accepted[encoding] = quality ? quality.split('=', 2).last.to_f : 1.0
        end
      end

      def compressible_content_type?(response)
        content_type = header(response.headers, 'content-type') || 'application/json'
        @content_types.any? { |allowed| content_type.start_with?(allowed) }
      end

      def compress(body, algorithm)
        case algorithm
        when 'gzip'
          gzip(body)
        when 'br'
          brotli_deflate(body)
        end
      end

      def decompress(body, algorithm)
        case algorithm
        when 'gzip'
          gunzip(body)
        when 'br'
          brotli_inflate(body)
        end
      end

      def gzip(body)
        require 'stringio'
        require 'zlib'

        buffer = StringIO.new
        writer = Zlib::GzipWriter.new(buffer)
        writer.write(body)
        writer.close
        buffer.string
      end

      def gunzip(body)
        require 'stringio'
        require 'zlib'

        reader = Zlib::GzipReader.new(StringIO.new(body.to_s))
        reader.read
      ensure
        reader&.close
      end

      def brotli_deflate(body)
        require 'brotli'
        Brotli.deflate(body)
      end

      def brotli_inflate(body)
        require 'brotli'
        Brotli.inflate(body.to_s)
      end

      def supported_algorithm?(algorithm)
        case algorithm
        when 'gzip'
          true
        when 'br'
          require 'brotli'
          true
        else
          false
        end
      rescue LoadError
        false
      end

      def parse_payload(body)
        JSON.parse(body)
      rescue JSON::ParserError
        body
      end

      def track_metrics(algorithm, original_size, compressed_size, duration)
        return unless @metrics && LePain.const_defined?(:Metrics)

        labels = { 'algorithm' => algorithm }
        LePain::Metrics.counter('compression_bytes_saved_total', 'Total bytes saved by response compression', labels: ['algorithm'])
                       .increment(labels, by: original_size - compressed_size)
        LePain::Metrics.histogram('compression_ratio', 'Response compression ratio', labels: ['algorithm'])
                       .observe(compressed_size.to_f / original_size, labels)
        LePain::Metrics.histogram('compression_duration_seconds', 'Response compression duration', labels: ['algorithm'])
                       .observe(duration, labels)
      end

      def header(headers, name)
        headers[name] || headers[name.split('-').map(&:capitalize).join('-')]
      end

      def append_vary(value, token)
        values = value.to_s.split(',').map(&:strip).reject(&:empty?)
        values << token unless values.any? { |existing| existing.casecmp?(token) }
        values.join(', ')
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    class RateLimit
      def initialize(**options)
        @limit = options.fetch(:limit, 100)
        @window = options.fetch(:window, 60)
        @store = {}
      end

      def call(request, context, next_handler)
        key = context.auth || request.headers['x-forwarded-for'] || 'anonymous'
        now = Time.now.to_i

        @store[key] ||= []
        @store[key].reject! { |t| t < now - @window }

        if @store[key].size >= @limit
          response = LePain::Response.error('Rate limit exceeded', status: 429)
          response.headers['Retry-After'] = @window.to_s
          response.headers['X-RateLimit-Limit'] = @limit.to_s
          response.headers['X-RateLimit-Remaining'] = '0'
          return response
        end

        @store[key] << now
        response = next_handler.call(request, context)
        response.headers['X-RateLimit-Limit'] = @limit.to_s
        response.headers['X-RateLimit-Remaining'] = (@limit - @store[key].size).to_s
        response
      end
    end
  end
end
