# frozen_string_literal: true

module LePain
  class Request
    attr_reader :action, :payload, :headers, :metadata, :transport, :raw

    def initialize(action:, payload: {}, headers: {}, metadata: {}, transport: :unknown, raw: nil)
      @action = action.to_s
      @payload = normalize_payload(payload)
      @headers = headers
      @metadata = normalize_metadata(metadata)
      @transport = transport
      @raw = raw
    end

    def [](key)
      @payload[key.to_s] || (@path_params && @path_params[key.to_s])
    end

    def fetch(key, default = nil)
      val = @payload[key.to_s]
      return val unless val.nil?

      val = @path_params[key.to_s] if @path_params
      return val unless val.nil?

      default
    end

    def meta(key)
      @metadata[key.to_s]
    end

    def to_h
      {
        action: @action,
        payload: @payload,
        headers: @headers,
        metadata: @metadata,
        transport: @transport,
      }
    end

    def self.from_http(method:, path:, body: {}, headers: {}, query: {})
      action = "#{method.upcase}:#{path}"
      normalized_query = query.transform_keys(&:to_s)
      payload = body.merge(normalized_query)
      new(action: action, payload: payload, headers: headers, metadata: { query: normalized_query }, transport: :http)
    end

    def self.from_mq(topic:, message:, metadata: {})
      new(action: topic, payload: message, metadata: metadata, transport: :mq)
    end

    private

    def normalize_payload(payload)
      return {} if payload.nil?

      if payload.is_a?(String)
        JSON.parse(payload)
      else
        payload.transform_keys(&:to_s)
      end
    end

    def normalize_metadata(metadata)
      return {} if metadata.nil?

      metadata.transform_keys(&:to_s)
    end
  end
end
