require 'spec_helper'
require 'le_pain/cache'
require 'tmpdir'

RSpec.describe LePain::Cache::Store do
  let(:store) { described_class.new(max_size: 3, default_ttl: 1) }

  describe '#get / #set' do
    it 'stores and retrieves values' do
      store.set('key', 'value')
      expect(store.get('key')).to eq('value')
    end

    it 'returns nil for missing keys' do
      expect(store.get('missing')).to be_nil
    end

    it 'uses namespace, tenant, and version prefixes' do
      store = described_class.new(namespace: 'orders', tenant: 'tenant-1', version: 'v2')
      store.set('123', 'value')

      expect(store.keys).to include('tenant-1:orders:v2:123')
      expect(store.get('123')).to eq('value')
    end
  end

  describe 'TTL expiry' do
    it 'expires entries after TTL' do
      store.set('key', 'value', ttl: 0.5)
      expect(store.get('key')).to eq('value')
      sleep 0.6
      expect(store.get('key')).to be_nil
    end
  end

  describe 'LRU eviction' do
    it 'evicts oldest entry when max_size reached' do
      store.set('key1', 'value1')
      store.set('key2', 'value2')
      store.set('key3', 'value3')
      store.get('key1')
      store.set('key4', 'value4')
      expect(store.get('key2')).to be_nil
      expect(store.get('key1')).to eq('value1')
      expect(store.get('key4')).to eq('value4')
    end
  end

  describe '#delete' do
    it 'removes entries' do
      store.set('key', 'value')
      store.delete('key')
      expect(store.get('key')).to be_nil
    end
  end

  describe '#fetch' do
    it 'returns cached value if present' do
      store.set('key', 'cached')
      result = store.fetch('key') { 'computed' }
      expect(result).to eq('cached')
    end

    it 'computes and caches if missing' do
      result = store.fetch('key') { 'computed' }
      expect(result).to eq('computed')
      expect(store.get('key')).to eq('computed')
    end
  end

  describe '#clear' do
    it 'removes all entries' do
      store.set('key1', 'value1')
      store.set('key2', 'value2')
      store.clear
      expect(store.size).to eq(0)
    end
  end

  describe '#cleanup' do
    it 'removes expired entries' do
      store.set('key1', 'value1', ttl: 0.1)
      store.set('key2', 'value2', ttl: 10)
      sleep 0.2
      store.cleanup
      expect(store.size).to eq(1)
      expect(store.get('key2')).to eq('value2')
    end
  end

  describe '#invalidate_tags' do
    it 'removes entries by tag' do
      store.set('user:1', 'one', tags: ['users'])
      store.set('order:1', 'order', tags: ['orders'])

      store.invalidate_tags('users')

      expect(store.get('user:1')).to be_nil
      expect(store.get('order:1')).to eq('order')
    end
  end
end

RSpec.describe LePain::Cache::RedisStore do
  class FakeRedisCache
    attr_reader :data, :sets

    def initialize
      @data = {}
      @sets = Hash.new { |hash, key| hash[key] = [] }
    end

    def get(key) = @data[key]
    def setex(key, _ttl, value) = @data[key] = value
    def del(*keys) = keys.each { |key| @data.delete(key); @sets.delete(key) }
    def keys(pattern) = @data.keys.select { |key| File.fnmatch(pattern, key) }
    def sadd(key, value) = @sets[key] << value
    def smembers(key) = @sets[key]
    def expire(_key, _ttl) = true
  end

  it 'stores values through redis and invalidates tags' do
    redis = FakeRedisCache.new
    store = described_class.new(redis: redis, namespace: 'svc')

    store.set('key', { 'value' => 1 }, tags: ['tag'])
    expect(store.get('key')).to eq({ 'value' => 1 })

    store.invalidate_tags('tag')
    expect(store.get('key')).to be_nil
  end
end

RSpec.describe LePain::Cache::MemcachedStore do
  class FakeMemcachedCache
    def initialize = @data = {}
    def get(key) = @data[key]
    def set(key, value, _ttl) = @data[key] = value
    def delete(key) = @data.delete(key)
    def flush = @data.clear
  end

  it 'stores values through a memcached-compatible client' do
    store = described_class.new(client: FakeMemcachedCache.new)

    store.set('key', 'value')
    expect(store.get('key')).to eq('value')
    store.delete('key')
    expect(store.get('key')).to be_nil
  end
end

RSpec.describe LePain::Cache::FileStore do
  it 'persists values to files and invalidates tags' do
    Dir.mktmpdir do |dir|
      store = described_class.new(path: dir)
      store.set('key', 'value', tags: ['tag'])

      reloaded = described_class.new(path: dir)
      expect(reloaded.get('key')).to eq('value')

      reloaded.invalidate_tags('tag')
      expect(reloaded.get('key')).to be_nil
    end
  end
end

RSpec.describe LePain::Cache do
  before do
    described_class.default_store = LePain::Cache::Store.new
    LePain::Metrics.instance_variable_set(:@registry, nil)
  end

  describe '.get / .set' do
    it 'uses default store' do
      described_class.set('key', 'value')
      expect(described_class.get('key')).to eq('value')
    end
  end

  describe '.fetch' do
    it 'fetches from default store' do
      result = described_class.fetch('key') { 'computed' }
      expect(result).to eq('computed')
    end
  end

  describe '.configure' do
    it 'builds default store from config' do
      described_class.configure(
        'store' => 'memory',
        'namespace' => 'orders',
        'version' => 'v1',
        'default_ttl' => 60,
        'max_size' => 10
      )

      described_class.set('1', 'order')
      expect(described_class.default_store.keys).to include('orders:v1:1')
    end
  end

  describe '.invalidate_tags' do
    it 'delegates to the default store' do
      described_class.set('key', 'value', tags: ['tag'])
      described_class.invalidate_tags('tag')
      expect(described_class.get('key')).to be_nil
    end
  end

  describe 'metrics' do
    it 'tracks cache hits and misses' do
      described_class.set('key', 'value')
      described_class.get('key')
      described_class.get('missing')

      output = LePain::Metrics.to_prometheus
      expect(output).to include('cache_operations_total{store="Store",result="hit"} 1')
      expect(output).to include('cache_operations_total{store="Store",result="miss"} 1')
    end
  end
end

RSpec.describe LePain::Cache::Cacheable do
  it 'caches instance methods' do
    service = Class.new do
      extend LePain::Cache::Cacheable
      attr_reader :calls

      def initialize = @calls = 0
      def lookup(id)
        @calls += 1
        "value-#{id}"
      end

      cache :lookup, key: ->(id) { "lookup:#{id}" }
    end.new

    expect(service.lookup(1)).to eq('value-1')
    expect(service.lookup(1)).to eq('value-1')
    expect(service.calls).to eq(1)
  end

  it 'caches class methods' do
    service = Class.new do
      extend LePain::Cache::Cacheable
      class << self
        attr_accessor :calls
      end
      self.calls = 0

      def self.lookup(id)
        self.calls += 1
        "value-#{id}"
      end

      cache :lookup, key: ->(id) { "class-lookup:#{id}" }
    end

    expect(service.lookup(1)).to eq('value-1')
    expect(service.lookup(1)).to eq('value-1')
    expect(service.calls).to eq(1)
  end
end
