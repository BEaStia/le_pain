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
        action = "#{method.to_s.upcase}:#{path}"
        route_metadata[action] = metadata
        action
      end

      def route_metadata
        @route_metadata ||= {}
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
    end

    def call(request, context)
      Context.set(context)

      validator_block = self.class.validators[request.action]
      if validator_block
        validator = Validation::Validator.new
        validator.instance_exec(&validator_block)
        errors = validator.validate(request.payload)
        return validation_error_response(errors) unless errors.empty?
      end

      schema = self.class.route_metadata.dig(request.action, :request)
      if schema && schema.respond_to?(:validate)
        errors = schema.validate(request.payload)
        return validation_error_response(errors) unless errors.empty?
      end

      self.class.before_filters.each do |filter|
        result = instance_exec(request, context, &filter)
        return result if result.is_a?(Response)
      end

      handler = self.class.handlers[request.action]
      return Response.not_found("no handler for #{request.action}") unless handler

      response = instance_exec(request, context, &handler)
      validate_response_schema(request, response)
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

    def validate_response_schema(request, response)
      schema = self.class.route_metadata.dig(request.action, :response)
      return unless schema && schema.respond_to?(:validate)
      return unless LePain::Application.config.dig('openapi', 'validation', 'responses')

      errors = schema.validate(response.body)
      raise Validation::ValidationError.new(errors) unless errors.empty?
    end
  end
end
