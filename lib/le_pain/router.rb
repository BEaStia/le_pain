# frozen_string_literal: true

module LePain
  class Router
    def initialize
      @routes = {}
      @middlewares = []
      @middleware_pipeline = Middleware::Pipeline.new
      @request_transformers = []
      @response_transformers = []
      @idempotency_store = nil
      @idempotency_key_extractor = nil
      @auth_extractor = ->(request) { request.headers['authorization'] }
      @request_logging = {
        enabled: false,
        log_body: false,
        log_headers: false,
        sensitive_fields: %w[authorization password password_hash token api_key secret],
      }
    end

    def auth_extractor(&block)
      @auth_extractor = block if block_given?
      @auth_extractor
    end

    def auth_header(header_name)
      @auth_extractor = ->(request) { request.headers[header_name.downcase] || request.headers[header_name] }
    end

    def auth_headers(*header_names)
      @auth_extractor = ->(request) { header_names.map { |h| request.headers[h.downcase] }.compact.first }
    end

    def register(action, handler_class)
      @routes[action.to_s] = handler_class
    end

    def route(action, &block)
      @routes[action.to_s] = block
    end

    def use(&block)
      @middlewares << block
    end

    def middleware(name, middleware_class, before: nil, after: nil, only: nil, except: nil, condition: nil, **options)
      if before && before != :handler
        @middleware_pipeline.insert_before(before, name, middleware_class, only: only, except: except, condition: condition, **options)
      elsif after
        @middleware_pipeline.insert_after(after, name, middleware_class, only: only, except: except, condition: condition, **options)
      else
        @middleware_pipeline.register(name, middleware_class, only: only, except: except, condition: condition, **options)
      end
    end

    def middleware_names
      @middleware_pipeline.names
    end

    def load_middleware_config(config)
      entries = config[:middleware] || config['middleware'] || config
      Array(entries).each do |entry|
        normalized = symbolize_keys(entry)
        name = normalized.fetch(:name).to_sym
        klass = normalized[:class] ? Object.const_get(normalized[:class].to_s) : Middleware.resolve(name)

        middleware(
          name,
          klass,
          before: normalized[:before]&.to_sym,
          after: normalized[:after]&.to_sym,
          only: normalized[:only],
          except: normalized[:except],
          **(normalized[:options] || {})
        )
      end
    end

    def transform_request(path: nil, transport: nil, content_type: nil, transformer: nil, &block)
      register_transformer(@request_transformers, path, transport, content_type, transformer || block)
    end

    def transform_response(path: nil, transport: nil, content_type: nil, transformer: nil, &block)
      register_transformer(@response_transformers, path, transport, content_type, transformer || block)
    end

    def idempotency(store: nil, key_extractor: nil, ttl: 3600)
      @idempotency_store = store || Idempotency::Store.new(ttl: ttl)
      @idempotency_key_extractor = key_extractor || ->(request, _context) { request.headers['idempotency-key'] || request['idempotency_key'] }
    end

    def configure_request_logging(config = {})
      normalized = symbolize_keys(config || {})
      @request_logging = @request_logging.merge(normalized)
    end

    def dispatch(request, context: nil)
      start_time = Time.now
      context ||= build_context(request)

      Context.with(context) do
        log_request(request)
        apply_request_transformers(request, context)
        idempotency_key = extract_idempotency_key(request, context)

        if idempotency_key && @idempotency_store
          cached = @idempotency_store.get(idempotency_key)
          if cached
            LePain::Application.logger.info("[#{context.request_id}] idempotent hit: #{idempotency_key}")
            log_response(request, cached, Time.now - start_time, extra: { cache: 'hit' })
            return cached
          end
        end

        @middlewares.each do |middleware|
          result = middleware.call(request, context)
          return result if result.is_a?(Response)
        end

        response = @middleware_pipeline.execute(request, context) do |req, ctx|
          dispatch_to_handler(req, ctx)
        end
        apply_response_transformers(request, context, response)

        duration = Time.now - start_time
        track_request_metrics(request, response, duration)

        if idempotency_key && @idempotency_store && response.success?
          @idempotency_store.set(idempotency_key, response)
          LePain::Application.logger.info("[#{context.request_id}] cached idempotent response: #{idempotency_key}")
        end

        log_response(request, response, duration)
        response
      end
    rescue StandardError => e
      LePain::Application.logger.error("router error: #{e.message}")
      Response.error('internal server error', status: 500)
    end

    def routes
      @routes.keys
    end

    private

    def dispatch_to_handler(request, context)
      handler, path_params = find_handler(request.action)
      return Response.not_found("no route for #{request.action}") unless handler

      request.instance_variable_set(:@path_params, path_params) if path_params

      if handler.is_a?(Class) && handler < Handler
        handler.call(request, context: context)
      elsif handler.respond_to?(:call)
        handler.call(request, context)
      else
        Response.error('invalid handler', status: 500)
      end
    end

    def log_request(request)
      return unless @request_logging[:enabled]

      method, path = method_and_path(request)
      extra = {
        event: 'request',
        method: method,
        path: path,
        transport: request.transport.to_s,
      }
      extra[:headers] = mask_hash(request.headers) if @request_logging[:log_headers]
      extra[:body] = mask_hash(request.payload) if @request_logging[:log_body]

      LePain::Application.logger.info('request received', extra: extra)
    end

    def log_response(request, response, duration, extra: {})
      return unless @request_logging[:enabled]

      method, path = method_and_path(request)
      fields = {
        event: 'response',
        method: method,
        path: path,
        status: response.status,
        duration: duration.round(6),
        duration_ms: (duration * 1000).round(3),
        transport: request.transport.to_s,
      }.merge(extra)
      fields[:headers] = mask_hash(response.headers) if @request_logging[:log_headers]
      fields[:body] = mask_hash(response.body) if @request_logging[:log_body]

      LePain::Application.logger.info('response sent', extra: fields)
    end

    def track_request_metrics(request, response, duration)
      method, path = method_and_path(request)

      if request.transport.to_sym == :mq
        Metrics.track_mq_message(
          topic: path,
          status: response.success? ? 'processed' : 'failed',
          duration: duration
        )
      else
        Metrics.track_http_request(
          method: method.to_s,
          path: path.to_s,
          status: response.status,
          duration: duration
        )
      end
    end

    def method_and_path(request)
      if request.action.to_s.include?(':')
        request.action.to_s.split(':', 2)
      else
        [nil, request.action.to_s]
      end
    end

    def mask_hash(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), masked|
          masked[key] = sensitive_field?(key) ? '[FILTERED]' : mask_hash(nested)
        end
      when Array
        value.map { |nested| mask_hash(nested) }
      else
        value
      end
    end

    def sensitive_field?(key)
      @request_logging[:sensitive_fields].map(&:to_s).include?(key.to_s.downcase)
    end

    def register_transformer(collection, path, transport, content_type, callable)
      raise ArgumentError, 'transformer block or callable is required' unless callable

      collection << {
        path: path,
        transport: transport,
        content_type: content_type,
        callable: callable,
      }
      callable
    end

    def apply_request_transformers(request, context)
      @request_transformers.each do |entry|
        next unless transformer_applies?(entry, request)

        call_transformer(entry[:callable], request, request, context)
      end
    end

    def apply_response_transformers(request, context, response)
      @response_transformers.each do |entry|
        next unless transformer_applies?(entry, request, response)

        call_transformer(entry[:callable], response, request, context)
      end
    end

    def call_transformer(callable, target, request, context)
      case callable.arity
      when 1
        callable.call(target)
      when 2
        callable.call(target, request)
      else
        callable.call(target, request, context)
      end
    end

    def transformer_applies?(entry, request, response = nil)
      path_matches?(entry[:path], request.action) &&
        transport_matches?(entry[:transport], request.transport) &&
        content_type_matches?(entry[:content_type], request, response)
    end

    def path_matches?(condition, action)
      return true unless condition

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

    def transport_matches?(condition, transport)
      return true unless condition

      Array(condition).map(&:to_sym).include?(transport.to_sym)
    end

    def content_type_matches?(condition, request, response)
      return true unless condition

      content_type = header_value(response&.headers || {}, 'content-type') ||
                     header_value(request.headers, 'content-type')
      return false unless content_type

      Array(condition).any? { |expected| content_type.start_with?(expected.to_s) }
    end

    def header_value(headers, name)
      headers[name] || headers[name.split('-').map(&:capitalize).join('-')]
    end

    def symbolize_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), result|
          result[key.to_sym] = symbolize_keys(nested)
        end
      when Array
        value.map { |nested| symbolize_keys(nested) }
      else
        value
      end
    end

    def find_handler(action)
      exact = @routes[action]
      return [exact, {}] if exact

      @routes.each do |pattern, handler|
        next unless pattern.include?(':')

        regex = pattern.gsub(/:([^\/]+)/, '(?<\1>[^/]+)')
        match = action.match(/^#{regex}$/)
        return [handler, match.names.zip(match.captures).to_h] if match
      end

      [nil, {}]
    end

    def extract_idempotency_key(request, context)
      return context.idempotency_key if context.idempotency_key
      return nil unless @idempotency_key_extractor

      @idempotency_key_extractor.call(request, context)
    end

    def build_context(request)
      request_id = request.headers['x-request-id'] || request.meta('request_id')
      trace_id = request.headers['x-trace-id'] || request.meta('trace_id') || request_id
      correlation_id = request.headers['x-correlation-id'] || request.meta('correlation_id') || trace_id
      idempotency_key = request.headers['idempotency-key'] || request['idempotency_key']
      auth = @auth_extractor.call(request)

      Context.new(
        request_id: request_id,
        trace_id: trace_id,
        correlation_id: correlation_id,
        idempotency_key: idempotency_key,
        transport: request.transport,
        metadata: request.metadata,
        auth: auth,
      )
    end
  end
end
