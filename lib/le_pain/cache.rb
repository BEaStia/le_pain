# frozen_string_literal: true

module LePain
  module Cache
    class Store
      def initialize(max_size: 1000, default_ttl: 300)
        @max_size = max_size
        @default_ttl = default_ttl
        @data = {}
        @mutex = Mutex.new
      end

      def get(key)
        @mutex.synchronize do
          entry = @data[key]
          return nil unless entry

          if entry[:expires_at] && entry[:expires_at] < Time.now
            @data.delete(key)
            return nil
          end

          entry[:value]
        end
      end

      def set(key, value, ttl: nil)
        @mutex.synchronize do
          evict_if_needed
          expires_at = ttl ? Time.now + ttl : (Time.now + @default_ttl)
          @data[key] = { value: value, expires_at: expires_at }
        end
      end

      def delete(key)
        @mutex.synchronize do
          @data.delete(key)
        end
      end

      def fetch(key, ttl: nil)
        value = get(key)
        return value if value

        value = yield
        set(key, value, ttl: ttl)
        value
      end

      def clear
        @mutex.synchronize do
          @data.clear
        end
      end

      def size
        @mutex.synchronize { @data.size }
      end

      def keys
        @mutex.synchronize { @data.keys }
      end

      def cleanup
        @mutex.synchronize do
          now = Time.now
          @data.reject! { |_, entry| entry[:expires_at] && entry[:expires_at] < now }
        end
      end

      private

      def evict_if_needed
        return unless @data.size >= @max_size

        # LRU eviction - remove oldest entry
        oldest_key = @data.keys.first
        @data.delete(oldest_key)
      end
    end

    module Cacheable
      def cache(method_name, key: nil, ttl: nil)
        original_method = instance_method(method_name)

        define_method(method_name) do |*args, **kwargs|
          cache_key = if key.respond_to?(:call)
                       key.call(*args, **kwargs)
                     elsif key
                       "#{key}:#{args.join(':')}"
                     else
                       "#{self.class.name}:#{method_name}:#{args.join(':')}"
                     end

          cache_store = self.class.cache_store || LePain::Cache.default_store
          cache_store.fetch(cache_key, ttl: ttl) do
            original_method.bind(self).call(*args, **kwargs)
          end
        end
      end

      def cache_store=(store)
        @cache_store = store
      end

      def cache_store
        @cache_store
      end
    end

    class << self
      def default_store
        @default_store ||= Store.new
      end

      def default_store=(store)
        @default_store = store
      end

      def get(key)
        default_store.get(key)
      end

      def set(key, value, ttl: nil)
        default_store.set(key, value, ttl: ttl)
      end

      def delete(key)
        default_store.delete(key)
      end

      def fetch(key, ttl: nil, &block)
        default_store.fetch(key, ttl: ttl, &block)
      end

      def clear
        default_store.clear
      end
    end
  end
end
