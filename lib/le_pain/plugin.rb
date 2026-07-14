# frozen_string_literal: true

module LePain
  module Plugin
    class Base
      attr_reader :name, :version, :config

      def initialize(name:, version: '1.0.0', config: {})
        @name = name
        @version = version
        @config = config
        @initialized = false
      end

      def configure(app, config)
        # Override in subclasses
      end

      def initialize_plugin(app)
        return if @initialized

        @initialized = true
        on_initialize(app)
      end

      def on_initialize(app)
        # Override in subclasses
      end

      def on_start(app)
        # Override in subclasses
      end

      def on_stop(app)
        # Override in subclasses
      end

      def initialized?
        @initialized
      end

      def to_h
        {
          name: @name,
          version: @version,
          initialized: @initialized,
          config: @config,
        }
      end
    end

    class Registry
      def initialize
        @plugins = {}
        @load_order = []
      end

      def register(plugin)
        raise ArgumentError, "Plugin #{plugin.name} already registered" if @plugins[plugin.name]

        @plugins[plugin.name] = plugin
        @load_order << plugin.name
        plugin
      end

      def get(name)
        @plugins[name.to_s]
      end

      def all
        @load_order.map { |name| @plugins[name] }
      end

      def names
        @load_order.dup
      end

      def size
        @plugins.size
      end

      def clear
        @plugins.clear
        @load_order.clear
      end

      def initialize_all(app)
        all.each { |plugin| plugin.initialize_plugin(app) }
      end

      def start_all(app)
        all.each { |plugin| plugin.on_start(app) }
      end

      def stop_all(app)
        all.reverse_each { |plugin| plugin.on_stop(app) }
      end

      def to_h
        all.map(&:to_h)
      end
    end

    class << self
      def registry
        @registry ||= Registry.new
      end

      def register(plugin)
        registry.register(plugin)
      end

      def get(name)
        registry.get(name)
      end

      def all
        registry.all
      end

      def initialize_all(app)
        registry.initialize_all(app)
      end

      def start_all(app)
        registry.start_all(app)
      end

      def stop_all(app)
        registry.stop_all(app)
      end

      def clear
        registry.clear
      end
    end
  end
end
