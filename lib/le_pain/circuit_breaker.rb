# frozen_string_literal: true

module LePain
  class CircuitBreaker
    STATES = %i[closed open half_open].freeze

    attr_reader :name, :state, :failure_count, :success_count, :last_failure_time, :last_success_time

    def initialize(name:, failure_threshold: 5, success_threshold: 2, timeout: 30, fallback: nil)
      @name = name
      @failure_threshold = failure_threshold
      @success_threshold = success_threshold
      @timeout = timeout
      @fallback = fallback
      @state = :closed
      @failure_count = 0
      @success_count = 0
      @last_failure_time = nil
      @last_success_time = nil
      @mutex = Mutex.new
    end

    def call(&block)
      @mutex.synchronize do
        case @state
        when :open
          if Time.now - @last_failure_time > @timeout
            transition_to(:half_open)
          else
            raise CircuitOpenError, "Circuit breaker '#{@name}' is open"
          end
        end
      end

      begin
        result = yield
        record_success
        result
      rescue StandardError => e
        record_failure
        raise
      end
    rescue CircuitOpenError
      if @fallback
        @fallback.call
      else
        raise
      end
    end

    def reset
      @mutex.synchronize do
        @state = :closed
        @failure_count = 0
        @success_count = 0
      end
    end

    def closed?
      @state == :closed
    end

    def open?
      @state == :open
    end

    def half_open?
      @state == :half_open
    end

    def to_h
      {
        name: @name,
        state: @state,
        failure_count: @failure_count,
        success_count: @success_count,
        last_failure_time: @last_failure_time&.iso8601,
        last_success_time: @last_success_time&.iso8601,
      }
    end

    private

    def record_success
      @mutex.synchronize do
        @success_count += 1
        @last_success_time = Time.now

        if @state == :half_open && @success_count >= @success_threshold
          transition_to(:closed)
        end
      end
    end

    def record_failure
      @mutex.synchronize do
        @failure_count += 1
        @last_failure_time = Time.now

        if @state == :half_open
          transition_to(:open)
        elsif @state == :closed && @failure_count >= @failure_threshold
          transition_to(:open)
        end
      end
    end

    def transition_to(new_state)
      old_state = @state
      @state = new_state

      case new_state
      when :closed
        @failure_count = 0
        @success_count = 0
      when :half_open
        @success_count = 0
      end

      LePain::Application.logger.info(
        "Circuit breaker '#{@name}' transitioned from #{old_state} to #{new_state}"
      )
    end
  end

  class CircuitOpenError < StandardError; end
end
