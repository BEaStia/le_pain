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
end
