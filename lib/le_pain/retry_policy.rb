# frozen_string_literal: true

module LePain
  class RetryPolicy
    STRATEGIES = %i[fixed exponential linear].freeze

    attr_reader :max_attempts, :strategy, :base_delay, :max_delay, :jitter, :retry_on

    def initialize(
      max_attempts: 3,
      strategy: :exponential,
      base_delay: 1.0,
      max_delay: 60.0,
      jitter: true,
      retry_on: [StandardError]
    )
      raise ArgumentError, "Invalid strategy: #{strategy}" unless STRATEGIES.include?(strategy)

      @max_attempts = max_attempts
      @strategy = strategy
      @base_delay = base_delay
      @max_delay = max_delay
      @jitter = jitter
      @retry_on = Array(retry_on)
    end

    def execute(&block)
      attempt = 0

      loop do
        attempt += 1
        begin
          return yield(attempt)
        rescue *retry_on => e
          raise if attempt >= max_attempts

          delay = calculate_delay(attempt)
          LePain::Application.logger.info(
            "Retry attempt #{attempt}/#{max_attempts} after #{delay.round(2)}s (error: #{e.message})"
          )
          sleep(delay)
        end
      end
    end

    def calculate_delay(attempt)
      delay = case @strategy
              when :fixed
                @base_delay
              when :linear
                @base_delay * attempt
              when :exponential
                @base_delay * (2 ** (attempt - 1))
              end

      delay = [delay, @max_delay].min
      delay = apply_jitter(delay) if @jitter
      delay
    end

    private

    def apply_jitter(delay)
      delay * (0.5 + rand * 0.5)
    end
  end
end
