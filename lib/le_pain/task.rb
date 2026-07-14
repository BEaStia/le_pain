# frozen_string_literal: true

require 'securerandom'
require 'time'

module LePain
  class Task
    STATES = %w[pending running completed failed cancelled].freeze

    attr_reader :id, :type, :state, :payload, :result, :error, :created_at, :started_at, :completed_at, :context, :attempts
    attr_accessor :updated_at

    def initialize(id: nil, type:, payload: {}, context: nil, state: 'pending', result: nil, error: nil, created_at: nil, updated_at: nil, started_at: nil, completed_at: nil, attempts: 0)
      @id = id || SecureRandom.uuid
      @type = type
      @state = state
      @payload = payload
      @result = result
      @error = error
      @context = context
      @attempts = attempts.to_i
      @created_at = created_at || Time.now
      @updated_at = updated_at || @created_at
      @started_at = started_at
      @completed_at = completed_at
    end

    def start!
      @state = 'running'
      @started_at = Time.now
      @updated_at = Time.now
    end

    def increment_attempt!
      @attempts += 1
      @updated_at = Time.now
    end

    def reset_for_retry!
      @state = 'pending'
      @result = nil
      @error = nil
      @attempts = 0
      @started_at = nil
      @completed_at = nil
      @updated_at = Time.now
    end

    def complete!(result)
      @state = 'completed'
      @result = result
      @completed_at = Time.now
      @updated_at = @completed_at
    end

    def fail!(error)
      @state = 'failed'
      @error = if error.respond_to?(:to_h) && error.to_h.is_a?(Hash) && error.to_h[:error].is_a?(Hash)
                 error.to_h[:error].merge(status: error.to_h[:status])
               else
                 { message: error.to_s, backtrace: error.respond_to?(:backtrace) ? error.backtrace&.first(5) : nil }
               end
      @completed_at = Time.now
      @updated_at = @completed_at
    end

    def cancel!
      @state = 'cancelled'
      @completed_at = Time.now
      @updated_at = @completed_at
    end

    def pending? = @state == 'pending'
    def running? = @state == 'running'
    def completed? = @state == 'completed'
    def failed? = @state == 'failed'
    def cancelled? = @state == 'cancelled'
    def finished? = completed? || failed? || cancelled?

    def duration
      return nil unless @completed_at
      (@completed_at - (@started_at || @created_at)).round(3)
    end

    def to_h
      {
        'id' => @id,
        'type' => @type,
        'state' => @state,
        'payload' => @payload,
        'result' => @result,
        'error' => @error,
        'context' => @context&.to_h,
        'attempts' => @attempts,
        'created_at' => @created_at.iso8601,
        'updated_at' => @updated_at.iso8601,
        'started_at' => @started_at&.iso8601,
        'completed_at' => @completed_at&.iso8601,
        'duration' => duration,
      }
    end

    def self.from_hash(data)
      ctx_data = data['context']
      context = ctx_data.is_a?(Hash) && ctx_data.key?('request_id') ? Context.new(
        request_id: ctx_data['request_id'],
        trace_id: ctx_data['trace_id'],
        correlation_id: ctx_data['correlation_id'],
        idempotency_key: ctx_data['idempotency_key'],
        transport: ctx_data['transport']&.to_sym,
        metadata: ctx_data['metadata'] || {},
        deadline: ctx_data['deadline'] ? Time.parse(ctx_data['deadline']) : nil,
        auth: ctx_data['auth'],
      ) : nil

      new(
        id: data['id'],
        type: data['type'],
        payload: data['payload'],
        state: data['state'],
        result: data['result'],
        error: data['error'],
        context: context,
        attempts: data['attempts'] || 0,
        created_at: Time.parse(data['created_at']),
        updated_at: Time.parse(data['updated_at']),
        started_at: data['started_at'] ? Time.parse(data['started_at']) : nil,
        completed_at: data['completed_at'] ? Time.parse(data['completed_at']) : nil,
      )
    end
  end
end
