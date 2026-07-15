# frozen_string_literal: true

require 'yaml'

module LePain
  module ConfigHotReload
    class Watcher
      attr_reader :config_path, :watch_interval, :reloadable_sections, :last_modified, :reload_count

      def initialize(config_path:, watch_interval: 5, reloadable_sections: nil)
        @config_path = config_path
        @watch_interval = watch_interval
        @reloadable_sections = reloadable_sections || %w[logger rate_limiting circuit_breakers]
        @last_modified = nil
        @reload_count = 0
        @running = false
        @thread = nil
        @callbacks = []
      end

      def start
        return if @running

        @running = true
        @last_modified = File.mtime(@config_path) if File.exist?(@config_path)

        @thread = Thread.new do
          while @running
            check_for_changes
            sleep @watch_interval
          end
        end

        LePain::Application.logger.info("Config hot reload watcher started (interval: #{@watch_interval}s)")
      end

      def stop
        @running = false
        @thread&.join(1)
        LePain::Application.logger.info("Config hot reload watcher stopped")
      end

      def on_reload(&block)
        @callbacks << block
      end

      def reload
        return { reloaded: [], failed: [] } unless File.exist?(@config_path)

        new_config = YAML.load_file(@config_path)
        reloaded = []
        failed = []

        @reloadable_sections.each do |section|
          next unless new_config.key?(section)

          begin
            apply_config(section, new_config[section])
            reloaded << section
          rescue StandardError => e
            LePain::Application.logger.error("Failed to reload #{section}: #{e.message}")
            failed << { section: section, error: e.message }
          end
        end

        @reload_count += 1
        @last_modified = File.mtime(@config_path)

        LePain::Application.logger.info("Config reloaded: #{reloaded.join(', ')}")
        @callbacks.each { |cb| cb.call(reloaded, failed) }

        { reloaded: reloaded, failed: failed }
      end

      def running?
        @running
      end

      def current_config
        return {} unless File.exist?(@config_path)

        YAML.load_file(@config_path)
      end

      private

      def check_for_changes
        return unless File.exist?(@config_path)

        current_mtime = File.mtime(@config_path)
        return if @last_modified && current_mtime <= @last_modified

        LePain::Application.logger.info("Config file changed, reloading...")
        reload
      end

      def apply_config(section, config)
        case section
        when 'logger'
          apply_logger_config(config)
        when 'rate_limiting'
          apply_rate_limiting_config(config)
        when 'circuit_breakers'
          apply_circuit_breakers_config(config)
        else
          LePain::Application.logger.warn("Unknown reloadable section: #{section}")
        end
      end

      def apply_logger_config(config)
        if config['level']
          level = case config['level'].to_s.downcase
                  when 'debug' then Logger::DEBUG
                  when 'info' then Logger::INFO
                  when 'warn' then Logger::WARN
                  when 'error' then Logger::ERROR
                  when 'fatal' then Logger::FATAL
                  else Logger::INFO
                  end
          LePain::Application.logger.level = level
        end
      end

      def apply_rate_limiting_config(config)
        # Rate limiting config would be applied to middleware
        # This is a placeholder for actual implementation
        LePain::Application.logger.debug("Rate limiting config reloaded: #{config}")
      end

      def apply_circuit_breakers_config(config)
        LePain::CircuitBreaker.configure(config)
        LePain::Application.logger.debug("Circuit breakers config reloaded: #{config}")
      end
    end

    class << self
      def watcher
        @watcher
      end

      def start(config_path:, watch_interval: 5, reloadable_sections: nil)
        @watcher = Watcher.new(
          config_path: config_path,
          watch_interval: watch_interval,
          reloadable_sections: reloadable_sections
        )
        @watcher.start
        @watcher
      end

      def stop
        @watcher&.stop
      end

      def reload
        @watcher&.reload
      end
    end
  end
end
