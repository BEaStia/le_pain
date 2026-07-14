# frozen_string_literal: true

require 'timeout'
require_relative 'retry_policy'

module LePain
  module Errors
    # Base error class
    class Base < StandardError
      attr_reader :code, :status, :context, :original_error

      def initialize(message = nil, code: nil, status: 500, context: {}, original_error: nil)
        super(message)
        @code = code || self.class.name.split('::').last.underscore
        @status = status
        @context = context
        @original_error = original_error
      end

      def to_h
        {
          status: @status,
          error: {
            code: @code,
            message: message,
            **@context,
            details: error_details
          }
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      private

      def error_details
        return nil unless @original_error

        {
          original_class: @original_error.class.name,
          original_message: @original_error.message
        }
      end
    end

    # Client errors (4xx)
    module ClientError
      class BadRequest < Base
        def initialize(message = 'Bad request', **opts)
          super(message, status: 400, **opts)
        end
      end

      class Unauthorized < Base
        def initialize(message = 'Unauthorized', **opts)
          super(message, status: 401, **opts)
        end
      end

      class Forbidden < Base
        def initialize(message = 'Forbidden', **opts)
          super(message, status: 403, **opts)
        end
      end

      class NotFound < Base
        def initialize(message = 'Not found', **opts)
          super(message, status: 404, **opts)
        end
      end

      class ValidationError < Base
        attr_reader :validation_errors

        def initialize(message = 'Validation failed', validation_errors: [], **opts)
          super(message, status: 422, **opts)
          @validation_errors = validation_errors
        end

        private

        def error_details
          (super || {}).merge(validation_errors: @validation_errors)
        end
      end
    end

    # Server errors (5xx)
    module ServerError
      class Base < Errors::Base; end

      class InternalError < Base
        def initialize(message = 'Internal server error', **opts)
          super(message, status: 500, **opts)
        end
      end

      class NotImplemented < Base
        def initialize(message = 'Not implemented', **opts)
          super(message, status: 501, **opts)
        end
      end

      class ServiceUnavailable < Base
        def initialize(message = 'Service unavailable', **opts)
          super(message, status: 503, **opts)
        end
      end
    end

    # Transient errors (retryable)
    module TransientError
      class Base < Errors::Base
        def retryable?
          true
        end
      end

      class Timeout < Base
        def initialize(message = 'Request timeout', **opts)
          super(message, status: 504, **opts)
        end
      end

      class ConnectionRefused < Base
        def initialize(message = 'Connection refused', **opts)
          super(message, status: 503, **opts)
        end
      end

      class RateLimited < Base
        def initialize(message = 'Rate limit exceeded', **opts)
          super(message, status: 429, **opts)
        end
      end
    end

    # Permanent errors (not retryable)
    module PermanentError
      class Base < Errors::Base
        def retryable?
          false
        end
      end

      class InvalidState < Base
        def initialize(message = 'Invalid state', **opts)
          super(message, status: 409, **opts)
        end
      end

      class BusinessRuleViolation < Base
        def initialize(message = 'Business rule violation', **opts)
          super(message, status: 422, **opts)
        end
      end
    end

    # Error handler with automatic strategies
    class Handler
      def initialize(config = {})
        @config = config
        @alert_callback = config[:alert_callback]
        @include_backtrace = config.fetch(:include_backtrace, false)
        @retry_policy = config[:retry_policy] || RetryPolicy.new
      end

      def handle(error, context: {})
        classified = classify(error)

        # Enrich error with context
        classified.context.merge!(
          request_id: context[:request_id],
          trace_id: context[:trace_id],
          correlation_id: context[:correlation_id]
        )
        classified.context[:backtrace] = Array(error.backtrace) if @include_backtrace

        # Apply strategy
        strategy = strategy_for(classified)
        strategy.call(classified)

        classified
      end

      def handle_operation(context: {}, retry_policy: @retry_policy, &block)
        raise ArgumentError, 'block is required' unless block

        attempt = 0

        loop do
          attempt += 1
          begin
            return yield(attempt)
          rescue StandardError => e
            classified = handle(e, context: context)
            return classified unless should_retry?(classified, attempt, retry_policy)

            delay = retry_policy.calculate_delay(attempt)
            LePain::Application.logger.info(
              "Retry attempt #{attempt}/#{retry_policy.max_attempts} after #{delay.round(2)}s (error: #{classified.message})"
            )
            sleep(delay)
          end
        end
      end

      private

      def classify(error)
        case error
        when Errors::Base
          error
        when Timeout::Error, Errno::ETIMEDOUT
          Errors::TransientError::Timeout.new(
            error.message,
            original_error: error
          )
        when Errno::ECONNREFUSED
          Errors::TransientError::ConnectionRefused.new(
            error.message,
            original_error: error
          )
        when ArgumentError, TypeError
          Errors::ClientError::BadRequest.new(
            error.message,
            original_error: error
          )
        when StandardError
          Errors::ServerError::InternalError.new(
            error.message,
            original_error: error
          )
        else
          Errors::ServerError::InternalError.new(
            'Unknown error',
            original_error: error
          )
        end
      end

      def strategy_for(error)
        if error.respond_to?(:retryable?) && error.retryable?
          ->(e) { log_transient(e) }
        elsif error.is_a?(Errors::PermanentError::Base)
          ->(e) { alert_ops(e) }
        elsif error.is_a?(Errors::ServerError::Base)
          ->(e) { alert_ops(e) }
        else
          ->(e) { log_client_error(e) }
        end
      end

      def log_transient(error)
        LePain::Application.logger.warn(
          "Transient error (will retry): #{error.code} - #{error.message}"
        )
      end

      def alert_ops(error)
        LePain::Application.logger.error(
          "Server error: #{error.code} - #{error.message}"
        )
        @alert_callback&.call(error)
      end

      def log_client_error(error)
        LePain::Application.logger.info(
          "Client error: #{error.code} - #{error.message}"
        )
      end

      def should_retry?(error, attempt, retry_policy)
        error.respond_to?(:retryable?) && error.retryable? && attempt < retry_policy.max_attempts
      end
    end
  end
end

# Helper for underscore conversion
class String
  def underscore
    gsub(/::/, '/')
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .tr('-', '_')
      .downcase
  end
end
