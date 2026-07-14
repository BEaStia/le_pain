# frozen_string_literal: true

module LePain
  class ShutdownHandler
    def initialize
      @callbacks = []
      @shutting_down = false
      @trap_queue = Queue.new
      @trap_thread = Thread.new { process_queue }
      @trap_thread.abort_on_exception = true
      setup_signals
    end

    def on_terminate(&block)
      @callbacks << block
    end

    def shut_down?
      @shutting_down
    end

    private

    def process_queue
      loop do
        @trap_queue.pop
        return if @shutting_down

        @shutting_down = true
        @callbacks.each(&:call)
        exit(0)
      end
    end

    def setup_signals
      %w[TERM INT].each do |signal|
        Signal.trap(signal) do
          @trap_queue << signal unless @shutting_down
        end
      end
    end
  end
end
