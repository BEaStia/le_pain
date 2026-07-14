require 'spec_helper'

RSpec.describe LePain::Idempotency::Store do
  let(:store) { described_class.new(ttl: 1) }

  describe '#get / #set' do
    it 'stores and retrieves responses' do
      resp = LePain::Response.success({ id: 1 })
      store.set('key-1', resp)
      expect(store.get('key-1')).to eq(resp)
    end

    it 'returns nil for missing keys' do
      expect(store.get('missing')).to be_nil
    end
  end

  describe 'TTL expiry' do
    it 'expires old entries' do
      resp = LePain::Response.success({ id: 1 })
      store.set('key-1', resp)
      sleep 1.1
      expect(store.get('key-1')).to be_nil
    end
  end

  describe '#delete' do
    it 'removes entries' do
      resp = LePain::Response.success({ id: 1 })
      store.set('key-1', resp)
      store.delete('key-1')
      expect(store.get('key-1')).to be_nil
    end
  end

  describe '#clear' do
    it 'removes all entries' do
      store.set('k1', LePain::Response.success({}))
      store.set('k2', LePain::Response.success({}))
      store.clear
      expect(store.get('k1')).to be_nil
      expect(store.get('k2')).to be_nil
    end
  end
end
