require 'spec_helper'

RSpec.describe LePain::Request do
  describe '.from_http' do
    it 'creates a request with HTTP transport' do
      req = described_class.from_http(method: 'POST', path: '/orders', body: { user_id: '1' })
      expect(req.transport).to eq(:http)
      expect(req.action).to eq('POST:/orders')
    end

    it 'merges body and query params' do
      req = described_class.from_http(
        method: 'GET', path: '/search',
        body: {}, query: { q: 'test', page: '1' },
      )
      expect(req['q']).to eq('test')
      expect(req['page']).to eq('1')
    end

    it 'normalizes symbol keys to strings' do
      req = described_class.from_http(
        method: 'POST', path: '/orders',
        body: { user_id: '1', items: ['a'] },
      )
      expect(req['user_id']).to eq('1')
      expect(req['items']).to eq(['a'])
    end
  end

  describe '.from_mq' do
    it 'creates a request with MQ transport' do
      req = described_class.from_mq(topic: 'orders.created', message: { user_id: '1' })
      expect(req.transport).to eq(:mq)
      expect(req.action).to eq('orders.created')
    end

    it 'accepts JSON string messages' do
      req = described_class.from_mq(topic: 'orders.created', message: '{"user_id":"1"}')
      expect(req['user_id']).to eq('1')
    end
  end

  describe '#[]' do
    it 'returns payload values by string key' do
      req = described_class.from_http(method: 'POST', path: '/test', body: { foo: 'bar' })
      expect(req['foo']).to eq('bar')
    end

    it 'returns path params when payload key not found' do
      req = described_class.from_http(method: 'GET', path: '/jobs/123', body: {})
      req.instance_variable_set(:@path_params, { 'id' => '123' })
      expect(req['id']).to eq('123')
    end
  end

  describe '#fetch' do
    it 'returns value when key exists' do
      req = described_class.from_http(method: 'POST', path: '/test', body: { foo: 'bar' })
      expect(req.fetch('foo')).to eq('bar')
    end

    it 'returns default when key not found' do
      req = described_class.from_http(method: 'POST', path: '/test', body: {})
      expect(req.fetch('missing', 'default')).to eq('default')
    end
  end

  describe '#meta' do
    it 'returns metadata values' do
      req = described_class.from_mq(topic: 'test', message: {}, metadata: { source: 'kafka' })
      expect(req.meta('source')).to eq('kafka')
    end
  end

  describe '#to_h' do
    it 'returns a hash representation' do
      req = described_class.from_http(method: 'POST', path: '/orders', body: { user_id: '1' })
      h = req.to_h
      expect(h[:action]).to eq('POST:/orders')
      expect(h[:transport]).to eq(:http)
    end
  end
end
