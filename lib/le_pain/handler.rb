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
        unless errors.empty?
          return Response.new(
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
      end

      self.class.before_filters.each do |filter|
        result = instance_exec(request, context, &filter)
        return result if result.is_a?(Response)
      end

      handler = self.class.handlers[request.action]
      return Response.not_found("no handler for #{request.action}") unless handler

      instance_exec(request, context, &handler)
    rescue StandardError => e
      LePain::Application.logger.error("handler error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      Response.error(e.message, status: 500)
    end
  end
end
