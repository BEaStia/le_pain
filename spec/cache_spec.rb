require 'spec_helper'
require 'le_pain/cache'

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
      store.set('key4', 'value4')
      expect(store.get('key1')).to be_nil
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
end

RSpec.describe LePain::Cache do
  before { described_class.clear }

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
end
