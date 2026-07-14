# frozen_string_literal: true

require 'securerandom'

module LePain
  class Context
    FIBER_KEY = :le_pain_context

    attr_reader :request_id, :trace_id, :correlation_id, :idempotency_key, :transport, :metadata, :deadline, :auth

    def initialize(request_id: nil, trace_id: nil, correlation_id: nil, idempotency_key: nil, transport: :unknown, metadata: {}, deadline: nil, auth: nil)
      @request_id = request_id || SecureRandom.uuid
      @trace_id = trace_id || @request_id
      @correlation_id = correlation_id || @trace_id
      @idempotency_key = idempotency_key
      @transport = transport
      @metadata = metadata
      @deadline = deadline
      @auth = auth
    end

    def with(new_metadata = {}, **overrides)
      dup.tap do |ctx|
        ctx.instance_variable_set(:@metadata, @metadata.merge(new_metadata))
        overrides.each do |key, value|
          ctx.instance_variable_set(:"@#{key}", value)
        end
      end
    end

    def [](key)
      @metadata[key]
    end

    def expired?
      @deadline ? Time.now > @deadline : false
    end

    def remaining_time
      return nil unless @deadline

      [@deadline.to_f - Time.now.to_f, 0].max
    end

    def self.current
      Fiber[FIBER_KEY] ||= new
    end

    def self.set(context)
      Fiber[FIBER_KEY] = context
    end

    def self.clear
      Fiber[FIBER_KEY] = nil
    end

    def self.with(context)
      previous = Fiber[FIBER_KEY]
      Fiber[FIBER_KEY] = context
      yield
    ensure
      Fiber[FIBER_KEY] = previous
    end

    def to_h
      {
        request_id: @request_id,
        trace_id: @trace_id,
        correlation_id: @correlation_id,
        idempotency_key: @idempotency_key,
        transport: @transport,
        metadata: @metadata,
        deadline: @deadline&.iso8601,
        auth: @auth,
      }
    end
  end
end
