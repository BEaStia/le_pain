# frozen_string_literal: true

module LePain
  class CircuitBreaker
    STATES = %i[closed open half_open].freeze

    attr_reader :name, :state, :failure_count, :success_count, :last_failure_time, :last_success_time

    class << self
      def registry
        @registry ||= {}
      end

      def get(name, **options)
        registry[name.to_s] ||= new(name: name.to_s, **options)
      end

      def register(name, breaker)
        registry[name.to_s] = breaker
      end

      def configure(config)
        config.to_h.each do |name, options|
          next if options == false

          opts = symbolize_options(options || {})
          register(name, new(name: name.to_s, **opts))
        end
      end

      def all
        registry.values
      end

      def clear
        registry.clear
      end

      private

      def symbolize_options(options)
        options.to_h.each_with_object({}) do |(key, value), result|
          next if key.to_s == 'fallback'

          result[key.to_sym] = value
        end
      end
    end

    def initialize(name:, failure_threshold: 5, success_threshold: 2, timeout: 30, fallback: nil, alert_callback: nil)
      @name = name
      @failure_threshold = failure_threshold
      @success_threshold = success_threshold
      @timeout = timeout
      @fallback = fallback
      @alert_callback = alert_callback
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
        record_state_metrics
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
      record_transition_metrics(old_state, new_state)
      alert_open if new_state == :open && old_state != :open
    end

    def record_transition_metrics(old_state, new_state)
      record_state_metrics
      return unless LePain.const_defined?(:Metrics)

      LePain::Metrics.counter(
        'circuit_breaker_transitions_total',
        'Circuit breaker state transitions',
        labels: %w[name from to]
      ).increment({ 'name' => @name, 'from' => old_state.to_s, 'to' => new_state.to_s })

      return unless new_state == :open

      LePain::Metrics.counter(
        'circuit_breaker_open_total',
        'Circuit breaker open transitions',
        labels: ['name']
      ).increment({ 'name' => @name })
    end

    def record_state_metrics
      return unless LePain.const_defined?(:Metrics)

      STATES.each do |state_name|
        LePain::Metrics.gauge(
          'circuit_breaker_state',
          'Circuit breaker state as one-hot gauge',
          labels: %w[name state]
        ).set(state_name == @state ? 1 : 0, { 'name' => @name, 'state' => state_name.to_s })
      end
    end

    def alert_open
      if @alert_callback
        @alert_callback.call(self)
      else
        LePain::Application.logger.error("Circuit breaker '#{@name}' opened")
      end
    end
  end

  class CircuitOpenError < StandardError; end
end
