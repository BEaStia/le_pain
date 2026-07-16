# frozen_string_literal: true

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
      contract_errors = validate_contract_request(contract, request)
      return validation_error_response(contract_errors) unless contract_errors.empty?

      self.class.before_filters.each do |filter|
        result = instance_exec(request, context, &filter)
        return result if result.is_a?(Response)
      end

      handler = self.class.handlers[handler_action]
      return Response.not_found("no handler for #{request.action}") unless handler

      response = instance_exec(request, context, &handler)
      validate_response_schema(contract, response)
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
