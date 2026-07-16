# frozen_string_literal: true

require 'digest'
require 'json'
require 'net/http'
require 'time'
require 'uri'

module LePain
  module Security
    class << self
      ENV_PATTERN = /\A\$\{([A-Z0-9_]+)(?::-(.*))?\}\z/i

      def secret_providers
        @secret_providers ||= {
          'vault' => VaultSecretProvider.new,
          'aws-sm' => AwsSecretsManagerProvider.new,
        }
      end

      def register_secret_provider(name, provider)
        secret_providers[name.to_s] = provider
      end

      def reset_secret_providers!
        @secret_providers = nil
      end

      def resolve_secrets(value)
        case value
        when Hash
          value.transform_values { |v| resolve_secrets(v) }
        when Array
          value.map { |v| resolve_secrets(v) }
        when String
          resolve_secret_string(value)
        else
          value
        end
      end

      private

      def resolve_secret_string(value)
        if (match = ENV_PATTERN.match(value))
          ENV.fetch(match[1], match[2])
        elsif value.start_with?('env:')
          ENV.fetch(value.delete_prefix('env:'), nil)
        elsif value.start_with?('vault:')
          resolve_provider_secret('vault', value.delete_prefix('vault:'))
        elsif value.start_with?('aws-sm:')
          resolve_provider_secret('aws-sm', value.delete_prefix('aws-sm:'))
        else
          value
        end
      end

      def resolve_provider_secret(provider_name, reference)
        path, key = reference.split('#', 2)
        secret_providers.fetch(provider_name).fetch(path, key: key)
      end
    end

    class VaultSecretProvider
      def initialize(address: ENV.fetch('VAULT_ADDR', nil), token: ENV.fetch('VAULT_TOKEN', nil))
        @address = address
        @token = token
      end

      def fetch(path, key: nil)
        raise ConfigurationError, 'VAULT_ADDR and VAULT_TOKEN are required for vault secrets' if @address.to_s.empty? || @token.to_s.empty?

        uri = URI.join(@address.end_with?('/') ? @address : "#{@address}/", "v1/#{path}")
        request = Net::HTTP::Get.new(uri)
        request['X-Vault-Token'] = @token
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(request) }
        raise ConfigurationError, "vault secret fetch failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        payload = JSON.parse(response.body)
        data = payload['data'].is_a?(Hash) && payload['data'].key?('data') ? payload['data']['data'] : payload['data']
        key ? data[key] : data
      end
    end

    class AwsSecretsManagerProvider
      def initialize(client: nil)
        @client = client
      end

      def fetch(secret_id, key: nil)
        client = @client || build_client
        response = client.get_secret_value(secret_id: secret_id)
        secret = response.respond_to?(:secret_string) ? response.secret_string : response[:secret_string]
        value = parse_secret(secret)
        key && value.is_a?(Hash) ? value[key] : value
      end

      private

      def build_client
        require 'aws-sdk-secretsmanager'

        Aws::SecretsManager::Client.new
      rescue LoadError
        raise ConfigurationError, 'aws-sdk-secretsmanager is required for aws-sm secrets'
      end

      def parse_secret(secret)
        JSON.parse(secret)
      rescue JSON::ParserError, TypeError
        secret
      end
    end

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
        @allowed_types = Array(options.fetch(:allowed_types, [])).compact.map(&:to_s)
      end

      def call(request, context, next_handler)
        content_length = request.headers['content-length']&.to_i

        if content_length && content_length > @max_size
          return LePain::Response.error(
            "Payload too large (max: #{@max_size} bytes)",
            status: 413
          )
        end

        content_type = header(request.headers, 'content-type')
        if @allowed_types.any? && content_type && !allowed_content_type?(content_type)
          return LePain::Response.error(
            "Unsupported content type: #{content_type}",
            status: 415,
            code: 'unsupported_content_type'
          )
        end

        next_handler.call(request, context)
      end

      private

      def allowed_content_type?(content_type)
        @allowed_types.any? { |allowed| content_type.to_s.split(';', 2).first.strip == allowed }
      end

      def header(headers, name)
        headers[name] || headers[name.split('-').map(&:capitalize).join('-')]
      end
    end

    class InputSanitizer
      SQL_PATTERNS = [
        /;\s*(drop|delete|insert|update|alter|truncate)\b/i,
        /\bunion\s+select\b/i,
        /'\s*or\s*'?1'?\s*=\s*'?1/i,
      ].freeze

      PATH_TRAVERSAL_PATTERN = %r{(?:^|[\\/])\.\.(?:[\\/]|$)|%2e%2e|%252e%252e}i
      XSS_REPLACEMENTS = {
        '&' => '&amp;',
        '<' => '&lt;',
        '>' => '&gt;',
        '"' => '&quot;',
        "'" => '&#39;',
      }.freeze

      def initialize(**options)
        @strip_null_bytes = options.fetch(:strip_null_bytes, true)
        @max_string_length = options.fetch(:max_string_length, 10_000)
        @reject_sql_patterns = options.fetch(:reject_sql_patterns, true)
        @reject_path_traversal = options.fetch(:reject_path_traversal, true)
        @escape_html = options.fetch(:escape_html, true)
      end

      def call(request, context, next_handler)
        if request.payload.is_a?(Hash)
          result = sanitize(request.payload)
          return violation_response(result[:violation]) if result[:violation]

          request.instance_variable_set(:@payload, result[:value])
        end
        next_handler.call(request, context)
      end

      private

      def sanitize(value)
        case value
        when Hash
          sanitized = {}
          value.each do |key, nested|
            result = sanitize(nested)
            return result if result[:violation]

            sanitized[key] = result[:value]
          end
          { value: sanitized }
        when Array
          sanitized = []
          value.each do |nested|
            result = sanitize(nested)
            return result if result[:violation]

            sanitized << result[:value]
          end
          { value: sanitized }
        when String
          sanitized = value.dup
          sanitized.delete!("\0") if @strip_null_bytes
          return violation('sql_injection') if @reject_sql_patterns && sql_injection?(sanitized)
          return violation('path_traversal') if @reject_path_traversal && path_traversal?(sanitized)

          sanitized = escape_html(sanitized) if @escape_html
          sanitized = sanitized[0, @max_string_length] if sanitized.length > @max_string_length
          { value: sanitized }
        else
          { value: value }
        end
      end

      def sql_injection?(value)
        SQL_PATTERNS.any? { |pattern| pattern.match?(value) }
      end

      def path_traversal?(value)
        PATH_TRAVERSAL_PATTERN.match?(value)
      end

      def escape_html(value)
        value.gsub(/[&<>"']/, XSS_REPLACEMENTS)
      end

      def violation(code)
        { violation: code }
      end

      def violation_response(code)
        LePain::Response.error("Security violation: #{code}", status: 400, code: code)
      end
    end

    class AuditLog
      def initialize(**options)
        @options = options
        @logger = options.fetch(:logger, LePain::Application.logger)
        @sensitive_fields = options.fetch(:sensitive_fields, %w[password token secret api_key])
        @previous_hash = options.fetch(:previous_hash, '0' * 64)
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
          log_entry[:event] = security_event(request, response)
          log_entry[:payload] = mask_hash(request.payload) if options_enabled?(:log_payload, false)
          log_entry[:previous_hash] = @previous_hash
          log_entry[:hash] = audit_hash(log_entry)
          @previous_hash = log_entry[:hash]

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

      private

      def options_enabled?(name, default)
        @options.fetch(name, default)
      end

      def security_event(request, response)
        return 'auth_failure' if response.status == 401 || response.status == 403
        return 'permission_change' if request.action.to_s.match?(%r{/(roles|permissions|acl)(?:/|$)}i)
        return 'sensitive_operation' if request.action.to_s.match?(%r{/(login|password|token|secret|admin)(?:/|$)}i)

        'request'
      end

      def audit_hash(entry)
        Digest::SHA256.hexdigest(JSON.generate(entry.reject { |key, _| key == :hash }))
      end

      def mask_hash(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), result|
            result[key] = sensitive?(key.to_s) ? '[FILTERED]' : mask_hash(nested)
          end
        when Array
          value.map { |nested| mask_hash(nested) }
        else
          value
        end
      end

      def sensitive?(key)
        @sensitive_fields.any? { |field| key.downcase.include?(field.to_s.downcase) }
      end
    end
  end
end
