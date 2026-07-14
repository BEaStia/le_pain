# frozen_string_literal: true

module LePain
  module Security
    class SecurityHeaders
      def initialize(**options)
        @x_frame_options = options.fetch(:x_frame_options, 'DENY')
        @x_content_type_options = options.fetch(:x_content_type_options, 'nosniff')
        @x_xss_protection = options.fetch(:x_xss_protection, '1; mode=block')
        @strict_transport_security = options.fetch(:strict_transport_security, 'max-age=31536000; includeSubDomains')
        @content_security_policy = options.fetch(:content_security_policy, "default-src 'self'")
        @referrer_policy = options.fetch(:referrer_policy, 'strict-origin-when-cross-origin')
      end

      def call(request, context, next_handler)
        response = next_handler.call(request, context)
        response.headers['X-Frame-Options'] = @x_frame_options
        response.headers['X-Content-Type-Options'] = @x_content_type_options
        response.headers['X-XSS-Protection'] = @x_xss_protection
        response.headers['Strict-Transport-Security'] = @strict_transport_security
        response.headers['Content-Security-Policy'] = @content_security_policy
        response.headers['Referrer-Policy'] = @referrer_policy
        response
      end
    end

    class PayloadLimit
      def initialize(**options)
        @max_size = options.fetch(:max_size, 1_048_576) # 1MB default
      end

      def call(request, context, next_handler)
        content_length = request.headers['content-length']&.to_i

        if content_length && content_length > @max_size
          return LePain::Response.error(
            "Payload too large (max: #{@max_size} bytes)",
            status: 413
          )
        end

        next_handler.call(request, context)
      end
    end

    class InputSanitizer
      def initialize(**options)
        @strip_null_bytes = options.fetch(:strip_null_bytes, true)
        @max_string_length = options.fetch(:max_string_length, 10_000)
      end

      def call(request, context, next_handler)
        if request.payload.is_a?(Hash)
          request.instance_variable_set(:@payload, sanitize(request.payload))
        end
        next_handler.call(request, context)
      end

      private

      def sanitize(value)
        case value
        when Hash
          value.transform_values { |v| sanitize(v) }
        when Array
          value.map { |v| sanitize(v) }
        when String
          sanitized = value.dup
          sanitized.delete!("\0") if @strip_null_bytes
          sanitized = sanitized[0, @max_string_length] if sanitized.length > @max_string_length
          sanitized
        else
          value
        end
      end
    end

    class AuditLog
      def initialize(**options)
        @logger = options.fetch(:logger, LePain::Application.logger)
        @sensitive_fields = options.fetch(:sensitive_fields, %w[password token secret api_key])
      end

      def call(request, context, next_handler)
        start_time = Time.now

        begin
          response = next_handler.call(request, context)
          duration = Time.now - start_time

          log_entry = {
            timestamp: Time.now.iso8601,
            request_id: context.request_id,
            trace_id: context.trace_id,
            action: request.action,
            transport: context.transport,
            duration: duration.round(3),
            status: response.status,
          }

          if response.status >= 400
            @logger.warn("SECURITY_AUDIT: #{log_entry.to_json}")
          else
            @logger.info("SECURITY_AUDIT: #{log_entry.to_json}")
          end

          response
        rescue StandardError => e
          @logger.error("SECURITY_AUDIT_ERROR: #{e.message}")
          raise
        end
      end
    end
  end
end
