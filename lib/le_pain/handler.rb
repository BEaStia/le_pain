# frozen_string_literal: true

require 'digest'
require 'json'

module LePain
  class Handler
    class << self
      def call(request, context: nil)
        context ||= Context.current
        new.call(request, context)
      end

      def handle(action, &block)
        handlers[action.to_s] = block
      end

      def get(path, **metadata)
        route('GET', path, **metadata)
      end

      def post(path, **metadata)
        route('POST', path, **metadata)
      end

      def put(path, **metadata)
        route('PUT', path, **metadata)
      end

      def patch(path, **metadata)
        route('PATCH', path, **metadata)
      end

      def delete(path, **metadata)
        route('DELETE', path, **metadata)
      end

      def route(method, path, **metadata)
        contract = EndpointContract.new(method: method, path: path, **metadata)
        endpoint_contracts[contract.action] = contract
        contract.action
      end

      def route_metadata
        endpoint_contracts.transform_values(&:metadata)
      end

      def endpoint_contracts
        @endpoint_contracts ||= {}
      end

      def endpoint_idempotency_store
        @endpoint_idempotency_store ||= Idempotency::Store.new
      end

      def endpoint_rate_limit_store
        @endpoint_rate_limit_store ||= {}
      end

      def handlers
        @handlers ||= {}
      end

      def validate(action, &block)
        validators[action.to_s] = block
      end

      def validators
        @validators ||= {}
      end

      def before_filter(&block)
        @before_filters ||= []
        @before_filters << block
      end

      def before_filters
        @before_filters ||= []
      end

      def resolve_action(action)
        action = action.to_s
        return action if handlers.key?(action) || endpoint_contracts.key?(action) || validators.key?(action)

        (handlers.keys + endpoint_contracts.keys + validators.keys).uniq.find do |pattern|
          action_matches?(pattern, action)
        end || action
      end

      private

      def action_matches?(pattern, action)
        return false unless pattern.include?(':')

        regex = pattern.gsub(/:([^\/]+)/, '(?<\1>[^/]+)')
        /^#{regex}$/.match?(action)
      end
    end

    def call(request, context)
      Context.set(context)

      handler_action = self.class.resolve_action(request.action)

      validator_block = self.class.validators[handler_action]
      if validator_block
        validator = Validation::Validator.new
        validator.instance_exec(&validator_block)
        errors = validator.validate(request.payload)
        return validation_error_response(errors) unless errors.empty?
      end

      contract = self.class.endpoint_contracts[handler_action]
      policy_response = apply_pre_validation_policies(contract, request, context)
      return policy_response if policy_response

      contract_errors = validate_contract_request(contract, request)
      return validation_error_response(contract_errors) unless contract_errors.empty?

      policy_response = apply_pre_handler_policies(contract, request, context)
      return policy_response if policy_response

      self.class.before_filters.each do |filter|
        result = instance_exec(request, context, &filter)
        return result if result.is_a?(Response)
      end

      handler = self.class.handlers[handler_action]
      return Response.not_found("no handler for #{request.action}") unless handler

      response = with_contract_metrics(contract) { instance_exec(request, context, &handler) }
      validate_response_schema(contract, response)
      apply_post_handler_policies(contract, request, context, response)
      response
    rescue StandardError => e
      LePain::Application.logger.error("handler error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      Response.error(e.message, status: 500)
    end

    private

    def validation_error_response(errors)
      Response.new(
        status: 400,
        error: {
          message: 'Validation failed',
          code: 'validation_error',
          details: errors.map(&:to_h),
        }
      ).tap do |resp|
        resp.instance_variable_set(:@validation_errors, errors.map(&:to_h))
      end
    end

    def apply_pre_validation_policies(contract, request, context)
      return nil unless contract

      return Response.unauthorized('Authentication required') if contract.auth_required? && blank?(context.auth)

      missing_permissions = contract.permissions - Array(metadata_value(context, 'permissions')).map(&:to_sym)
      return forbidden("Missing permissions: #{missing_permissions.join(', ')}") if missing_permissions.any?

      missing_scopes = contract.scopes - Array(metadata_value(context, 'scopes')).map(&:to_sym)
      return forbidden("Missing scopes: #{missing_scopes.join(', ')}") if missing_scopes.any?

      rate_limit_response(contract, request, context)
    end

    def apply_pre_handler_policies(contract, request, context)
      return nil unless contract

      cached_idempotent_response(contract, request, context) || cached_contract_response(contract, request, context)
    end

    def apply_post_handler_policies(contract, request, context, response)
      return unless contract

      store_idempotent_response(contract, request, context, response)
      store_contract_cache(contract, request, context, response)
    end

    def forbidden(message)
      Response.error(message, status: 403, code: 'forbidden')
    end

    def rate_limit_response(contract, request, context)
      return nil unless contract.rate_limited?

      options = contract.rate_limit.is_a?(Hash) ? contract.rate_limit : {}
      limit = (options[:limit] || options['limit'] || 100).to_i
      window = (options[:window] || options['window'] || 60).to_i
      key = policy_key(options[:key] || options['key'], contract, request, context)
      now = Time.now.to_i
      store_key = "#{contract.action}:#{key}"
      store = self.class.endpoint_rate_limit_store
      store[store_key] ||= []
      store[store_key].reject! { |timestamp| timestamp < now - window }

      if store[store_key].size >= limit
        response = Response.error('Rate limit exceeded', status: 429, code: 'rate_limited')
        response.headers['Retry-After'] = window.to_s
        response.headers['X-RateLimit-Limit'] = limit.to_s
        response.headers['X-RateLimit-Remaining'] = '0'
        return response
      end

      store[store_key] << now
      nil
    end

    def cached_idempotent_response(contract, request, context)
      return nil unless contract.idempotency_enabled?

      key = idempotency_key(contract, request, context)
      return nil if blank?(key)

      self.class.endpoint_idempotency_store.get(key)
    end

    def store_idempotent_response(contract, request, context, response)
      return unless contract.idempotency_enabled? && response.success?

      key = idempotency_key(contract, request, context)
      self.class.endpoint_idempotency_store.set(key, response) unless blank?(key)
    end

    def cached_contract_response(contract, request, context)
      return nil unless contract.cache_enabled?

      Cache.get(cache_key(contract, request, context))
    end

    def store_contract_cache(contract, request, context, response)
      return unless contract.cache_enabled? && response.success?

      options = contract.cache.is_a?(Hash) ? contract.cache : {}
      Cache.set(
        cache_key(contract, request, context),
        response,
        ttl: options[:ttl] || options['ttl'],
        tags: Array(options[:tags] || options['tags'])
      )
    end

    def cache_key(contract, request, context)
      options = contract.cache.is_a?(Hash) ? contract.cache : {}
      policy_key(options[:key] || options['key'], contract, request, context)
    end

    def idempotency_key(contract, request, context)
      options = contract.idempotency.is_a?(Hash) ? contract.idempotency : {}
      key_config = options[:key] || options['key']
      return policy_key(key_config, contract, request, context) if key_config

      context.idempotency_key || request.headers['idempotency-key'] || request['idempotency_key']
    end

    def policy_key(key_config, contract, request, context)
      case key_config
      when Proc
        key_config.call(request, context)
      when Symbol, String
        request[key_config] || request.headers[key_config.to_s] || metadata_value(context, key_config.to_s)
      else
        digest = Digest::SHA256.hexdigest(JSON.generate(request.payload.sort.to_h))
        "#{contract.action}:#{context.auth || 'anonymous'}:#{digest}"
      end
    end

    def with_contract_metrics(contract)
      return yield unless contract && LePain.const_defined?(:Metrics)

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = yield
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      LePain::Metrics.counter('endpoint_contract_requests_total', 'Endpoint contract requests', labels: %w[action status])
                     .increment({ 'action' => contract.action, 'status' => response.status.to_s })
      LePain::Metrics.histogram('endpoint_contract_duration_seconds', 'Endpoint contract duration', labels: ['action'])
                     .observe(duration, { 'action' => contract.action })
      LePain::Application.logger.info('endpoint contract handled', extra: { action: contract.action, policies: contract.policies.keys }) if contract.policies.any?
      response
    end

    def metadata_value(context, key)
      context.metadata[key] || context.metadata[key.to_sym]
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def validate_contract_request(contract, request)
      return [] unless contract

      errors = []
      errors.concat(validate_contract_schema(contract.request_schema, request.payload))
      errors.concat(validate_contract_schema(contract.params_schema, request.instance_variable_get(:@path_params) || {}))
      errors.concat(validate_contract_schema(contract.query_schema, request.metadata.fetch('query', {})))
      errors.concat(validate_contract_schema(contract.headers_schema, request.headers))
      errors
    end

    def validate_contract_schema(schema, payload)
      return [] unless schema && schema.respond_to?(:validate)

      schema.validate(payload)
    end

    def validate_response_schema(contract, response)
      schema = contract&.response_schema
      return unless schema && schema.respond_to?(:validate)
      return unless LePain::Application.config.dig('openapi', 'validation', 'responses')

      errors = schema.validate(response.body)
      raise Validation::ValidationError.new(errors) unless errors.empty?
    end
  end
end
