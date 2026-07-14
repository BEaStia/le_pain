# frozen_string_literal: true

require_relative 'task_stores/base'
require_relative 'task_stores/memory_store'
require_relative 'task_stores/file_store'

module LePain
  module TaskStores
    class << self
      def register(name, adapter_class)
        @adapters ||= {}
        @adapters[name.to_sym] = adapter_class
      end

      def resolve(name, **options)
        @adapters ||= {}
        adapter_class = @adapters[name.to_sym]
        raise ConfigurationError, "unknown task store: #{name}" unless adapter_class

        adapter_class.new(**options)
      end

      def adapters
        @adapters ||= {}
        @adapters.dup
      end
    end

    register :memory, MemoryStore
    register :file, FileStore

    begin
      require_relative 'task_stores/postgres_store'
      register :postgres, PostgresStore
    rescue LoadError
    end

    begin
      require_relative 'task_stores/redis_store'
      register :redis, RedisStore
    rescue LoadError
    end

    begin
      require_relative 'task_stores/sqlite_store'
      register :sqlite, SqliteStore
    rescue LoadError
    end
  end
end
