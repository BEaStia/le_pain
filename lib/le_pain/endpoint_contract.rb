# frozen_string_literal: true

module LePain
  class EndpointContract
    SCHEMA_KEYS = %i[params query headers request response].freeze
    POLICY_KEYS = %i[auth permissions scopes idempotency rate_limit cache].freeze
    DOC_KEYS = %i[summary description tags responses security request_body parameters].freeze

    attr_reader :method, :path, :action, :metadata

    def initialize(method:, path:, **metadata)
      @method = method.to_s.upcase
      @path = normalize_path(path)
      @action = "#{@method}:#{@path}"
      @metadata = metadata
      validate!
    end

    def request_schema = metadata[:request]
    def response_schema = metadata[:response]
    def params_schema = metadata[:params]
    def query_schema = metadata[:query]
    def headers_schema = metadata[:headers]
    def auth = metadata[:auth]
    def permissions = Array(metadata[:permissions]).map(&:to_sym)
    def scopes = Array(metadata[:scopes]).map(&:to_sym)
    def idempotency = metadata[:idempotency]
    def rate_limit = metadata[:rate_limit]
    def cache = metadata[:cache]

    def auth_required?
      auth == true || auth == :required || auth.to_s == 'required' || permissions.any? || scopes.any?
    end

    def idempotency_enabled?
      !!idempotency
    end

    def rate_limited?
      !!rate_limit
    end

    def cache_enabled?
      !!cache
    end

    def schemas
      SCHEMA_KEYS.filter_map { |key| metadata[key] }.select { |schema| schema.respond_to?(:to_openapi_schema) }
    end

    def docs
      metadata.slice(*DOC_KEYS)
    end

    def policies
      metadata.slice(*POLICY_KEYS)
    end

    def to_h
      {
        method: method,
        path: path,
        action: action,
        schemas: SCHEMA_KEYS.each_with_object({}) { |key, result| result[key] = schema_name(metadata[key]) if metadata[key] },
        docs: docs,
        policies: policies,
      }
    end

    private

    def normalize_path(path)
      path = path.to_s
      path.start_with?('/') ? path : "/#{path}"
    end

    def validate!
      raise ArgumentError, 'method is required' if method.empty?
      raise ArgumentError, 'path must start with /' unless path.start_with?('/')

      SCHEMA_KEYS.each do |key|
        schema = metadata[key]
        next unless schema
        next if schema.respond_to?(:validate) && schema.respond_to?(:to_openapi_schema)

        raise ArgumentError, "#{key} must be a LePain::Schema-compatible class"
      end
    end

    def schema_name(schema)
      schema.respond_to?(:schema_name) ? schema.schema_name : schema.to_s
    end
  end

  module EndpointContracts
    class Linter
      def self.lint(router)
        new(router).lint
      end

      def initialize(router)
        @router = router
      end

      def lint
        @router.route_handlers.each_with_object([]) do |(action, handler), warnings|
          contract = @router.endpoint_contracts[action]
          warnings << "Route #{action} has no endpoint contract" unless contract
          next unless contract

          warnings << "Route #{action} has no response schema" unless contract.response_schema
          warnings << "Route #{action} has no request schema" if %w[POST PUT PATCH].include?(contract.method) && !contract.request_schema
        end
      end
    end

    module TestHelpers
      def build_contract_request(contract, body: {}, query: {}, headers: {}, params: {})
        Request.from_http(
          method: contract.method,
          path: expand_path(contract.path, params),
          body: body,
          query: query,
          headers: headers
        )
      end

      private

      def expand_path(path, params)
        params.each_with_object(path.dup) do |(key, value), expanded|
          expanded.gsub!(":#{key}", value.to_s)
        end
      end
    end

    class ClientStubGenerator
      def self.generate(router, module_name: 'ApiClient')
        lines = ["module #{module_name}"]
        router.endpoint_contracts.values.each do |contract|
          method_name = contract.path.gsub(%r{^/}, '').gsub(/:[^\/]+/, 'by_id').gsub(/[^a-zA-Z0-9]+/, '_').gsub(/_+\z/, '')
          method_name = "#{contract.method.downcase}_#{method_name}"
          lines << "  def #{method_name}(payload: {}, headers: {})"
          lines << "    request(:#{contract.method.downcase}, '#{contract.path}', payload: payload, headers: headers)"
          lines << '  end'
          lines << ''
        end
        lines << 'end'
        lines.join("\n")
      end
    end
  end
end
