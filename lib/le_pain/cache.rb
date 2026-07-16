# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'tmpdir'

module LePain
  module Cache
    class Store
      attr_reader :namespace, :version

      def initialize(max_size: 1000, default_ttl: 300, namespace: nil, version: nil, service: nil, tenant: nil)
        @max_size = max_size
        @default_ttl = default_ttl
        @namespace = namespace || service
        @version = version
        @tenant = tenant
        @data = {}
        @tags = Hash.new { |hash, tag| hash[tag] = {} }
        @mutex = Mutex.new
      end

      def get(key)
        cache_key = normalize_key(key)
        @mutex.synchronize do
          entry = @data[cache_key]
          unless entry
            track_cache(:miss)
            return nil
          end

          if entry[:expires_at] && entry[:expires_at] < Time.now
            delete_entry(cache_key, entry)
            track_cache(:miss)
            return nil
          end

          @data.delete(cache_key)
          @data[cache_key] = entry
          track_cache(:hit)
          entry[:value]
        end
      end

      def set(key, value, ttl: nil, tags: [])
        cache_key = normalize_key(key)
        @mutex.synchronize do
          evict_if_needed
          expires_at = ttl ? Time.now + ttl : (Time.now + @default_ttl)
          entry = { value: value, expires_at: expires_at, tags: Array(tags).map(&:to_s) }
          @data[cache_key] = entry
          index_tags(cache_key, entry[:tags])
        end
      end

      def delete(key)
        cache_key = normalize_key(key)
        @mutex.synchronize do
          entry = @data[cache_key]
          delete_entry(cache_key, entry) if entry
        end
      end

      def fetch(key, ttl: nil, tags: [])
        value = get(key)
        return value unless value.nil?

        value = yield
        set(key, value, ttl: ttl, tags: tags)
        value
      end

      def clear
        @mutex.synchronize do
          @data.clear
          @tags.clear
        end
      end

      def size
        @mutex.synchronize { @data.size }
      end

      def keys
        @mutex.synchronize { @data.keys }
      end

      def invalidate_tags(*tags)
        normalized_tags = tags.flatten.compact.map(&:to_s)
        @mutex.synchronize do
          normalized_tags.each do |tag|
            @tags[tag].keys.each { |key| delete_entry(key, @data[key]) if @data[key] }
            @tags.delete(tag)
          end
        end
      end

      def cleanup
        @mutex.synchronize do
          now = Time.now
          @data.each do |key, entry|
            delete_entry(key, entry) if entry[:expires_at] && entry[:expires_at] < now
          end
        end
      end

      def normalize_key(key)
        [
          @tenant,
          @namespace,
          @version,
          key,
        ].compact.reject(&:empty?).join(':')
      end

      private

      def evict_if_needed
        return unless @data.size >= @max_size

        # LRU eviction - remove oldest entry
        oldest_key = @data.keys.first
        delete_entry(oldest_key, @data[oldest_key])
      end

      def index_tags(key, tags)
        tags.each { |tag| @tags[tag][key] = true }
      end

      def delete_entry(key, entry)
        @data.delete(key)
        Array(entry&.dig(:tags)).each { |tag| @tags[tag].delete(key) }
      end

      def track_cache(result)
        return unless LePain.const_defined?(:Metrics)

        LePain::Metrics.counter('cache_operations_total', 'Total cache operations', labels: %w[store result])
                       .increment({ 'store' => self.class.name.split('::').last, 'result' => result.to_s })
      end
    end

    class RedisStore < Store
      def initialize(redis: nil, url: nil, **options)
        super(**options)
        @redis = redis || build_redis(url)
      end

      def get(key)
        cache_key = normalize_key(key)
        raw = @redis.get(cache_key)
        if raw.nil?
          track_cache(:miss)
          return nil
        end

        track_cache(:hit)
        Marshal.load(raw)
      end

      def set(key, value, ttl: nil, tags: [])
        cache_key = normalize_key(key)
        ttl ||= @default_ttl
        @redis.setex(cache_key, ttl.to_i, Marshal.dump(value))
        Array(tags).each do |tag|
          tag_key = tag_index_key(tag)
          @redis.sadd(tag_key, cache_key)
          @redis.expire(tag_key, ttl.to_i) if @redis.respond_to?(:expire)
        end
        value
      end

      def delete(key)
        @redis.del(normalize_key(key))
      end

      def clear
        keys = @redis.keys("#{key_prefix}*")
        @redis.del(*keys) if keys.any?
      end

      def invalidate_tags(*tags)
        tags.flatten.compact.each do |tag|
          tag_key = tag_index_key(tag)
          keys = Array(@redis.smembers(tag_key))
          @redis.del(*keys) if keys.any?
          @redis.del(tag_key)
        end
      end

      private

      def build_redis(url)
        require 'redis'

        Redis.new(url: url)
      rescue LoadError
        raise ConfigurationError, 'redis gem is required for Redis cache store'
      end

      def key_prefix
        normalize_key('')
      end

      def tag_index_key(tag)
        "#{key_prefix}:tags:#{tag}"
      end
    end

    class MemcachedStore < Store
      def initialize(client: nil, servers: nil, **options)
        super(**options)
        @client = client || build_client(servers)
      end

      def get(key)
        value = @client.get(normalize_key(key))
        track_cache(value.nil? ? :miss : :hit)
        value
      end

      def set(key, value, ttl: nil, tags: [])
        @client.set(normalize_key(key), value, ttl || @default_ttl)
        value
      end

      def delete(key)
        @client.delete(normalize_key(key))
      end

      def clear
        @client.flush if @client.respond_to?(:flush)
      end

      private

      def build_client(servers)
        require 'dalli'

        Dalli::Client.new(servers)
      rescue LoadError
        raise ConfigurationError, 'dalli gem is required for Memcached cache store'
      end
    end

    class FileStore < Store
      def initialize(path:, **options)
        super(**options)
        @path = path
        FileUtils.mkdir_p(@path)
      end

      def get(key)
        cache_key = normalize_key(key)
        file = file_for(cache_key)
        unless File.exist?(file)
          track_cache(:miss)
          return nil
        end

        entry = Marshal.load(File.binread(file))
        if entry[:expires_at] && entry[:expires_at] < Time.now
          FileUtils.rm_f(file)
          track_cache(:miss)
          return nil
        end

        track_cache(:hit)
        entry[:value]
      end

      def set(key, value, ttl: nil, tags: [])
        cache_key = normalize_key(key)
        expires_at = Time.now + (ttl || @default_ttl)
        File.binwrite(file_for(cache_key), Marshal.dump(value: value, expires_at: expires_at, tags: Array(tags).map(&:to_s)))
        index_file_tags(cache_key, tags)
        value
      end

      def delete(key)
        FileUtils.rm_f(file_for(normalize_key(key)))
      end

      def clear
        FileUtils.rm_f(Dir.glob(File.join(@path, '*')))
      end

      def invalidate_tags(*tags)
        tags.flatten.compact.map(&:to_s).each do |tag|
          tag_file = tag_file_for(tag)
          next unless File.exist?(tag_file)

          Marshal.load(File.binread(tag_file)).each { |key| FileUtils.rm_f(file_for(key)) }
          FileUtils.rm_f(tag_file)
        end
      end

      private

      def file_for(key)
        File.join(@path, Digest::SHA256.hexdigest(key))
      end

      def tag_file_for(tag)
        File.join(@path, "tag-#{Digest::SHA256.hexdigest(tag)}")
      end

      def index_file_tags(key, tags)
        Array(tags).map(&:to_s).each do |tag|
          file = tag_file_for(tag)
          keys = File.exist?(file) ? Marshal.load(File.binread(file)) : []
          keys << key unless keys.include?(key)
          File.binwrite(file, Marshal.dump(keys))
        end
      end
    end

    module Cacheable
      def cache(method_name, key: nil, ttl: nil)
        if method_defined?(method_name)
          cache_instance_method(method_name, key: key, ttl: ttl)
        elsif singleton_class.method_defined?(method_name)
          cache_singleton_method(method_name, key: key, ttl: ttl)
        else
          raise NameError, "undefined method `#{method_name}` for cache"
        end
      end

      def cache_instance_method(method_name, key: nil, ttl: nil)
        original_method = instance_method(method_name)

        define_method(method_name) do |*args, **kwargs|
          cache_key = self.class.build_cache_key(method_name, args, kwargs, key)

          cache_store = self.class.cache_store || LePain::Cache.default_store
          cache_store.fetch(cache_key, ttl: ttl) do
            original_method.bind(self).call(*args, **kwargs)
          end
        end
      end

      def cache_singleton_method(method_name, key: nil, ttl: nil)
        original_method = method(method_name)
        define_singleton_method(method_name) do |*args, **kwargs|
          cache_key = build_cache_key(method_name, args, kwargs, key)
          cache_store = self.cache_store || LePain::Cache.default_store
          cache_store.fetch(cache_key, ttl: ttl) { original_method.call(*args, **kwargs) }
        end
      end

      def build_cache_key(method_name, args, kwargs, key)
        if key.respond_to?(:call)
          key.call(*args, **kwargs)
        elsif key
          "#{key}:#{args.join(':')}"
        else
          parts = args + kwargs.sort.flatten
          "#{name}:#{method_name}:#{parts.join(':')}"
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

      def configure(config = {})
        normalized = config.to_h.transform_keys(&:to_s)
        @default_store = build_store(normalized)
      end

      def build_store(config = {})
        options = {
          default_ttl: (config['default_ttl'] || 300).to_i,
          namespace: config['namespace'] || config['service'],
          version: config['version'],
          tenant: config['tenant'],
        }.compact

        case (config['store'] || 'memory').to_s
        when 'memory'
          Store.new(max_size: (config['max_size'] || config['max_entries'] || 1000).to_i, **options)
        when 'redis'
          RedisStore.new(url: config['url'], **options)
        when 'memcached'
          MemcachedStore.new(servers: config['servers'], **options)
        when 'file'
          FileStore.new(path: config['path'] || File.join(Dir.tmpdir, 'le_pain-cache'), **options)
        else
          raise ConfigurationError, "unknown cache store: #{config['store']}"
        end
      end

      def get(key)
        default_store.get(key)
      end

      def set(key, value, ttl: nil, tags: [])
        default_store.set(key, value, ttl: ttl, tags: tags)
      end

      def delete(key)
        default_store.delete(key)
      end

      def fetch(key, ttl: nil, tags: [], &block)
        default_store.fetch(key, ttl: ttl, tags: tags, &block)
      end

      def clear
        default_store.clear
      end

      def invalidate_tags(*tags)
        default_store.invalidate_tags(*tags)
      end
    end
  end
end
