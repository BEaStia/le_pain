require 'spec_helper'
require 'le_pain/test'

RSpec.describe LePain::Test::Helpers do
  include described_class

  let(:handler_class) do
    Class.new(LePain::Handler) do
      handle 'POST:/orders' do |req, ctx|
        LePain::Response.success({ order_id: req['user_id'] }, status: 201)
      end

      handle 'orders.created' do |req, ctx|
        LePain::Response.success({ user_id: req['user_id'] })
      end

      handle 'GET:/health' do |_req, _ctx|
        LePain::Response.success({ status: 'ok' })
      end
    end
  end

  before do
    LePain::Application.router.register('POST:/orders', handler_class)
    LePain::Application.router.register('orders.created', handler_class)
    LePain::Application.router.register('GET:/health', handler_class)
  end

  describe '#dispatch' do
    it 'dispatches HTTP requests' do
      resp = dispatch('POST:/orders', body: { user_id: '123' })
      expect(resp.status).to eq(201)
      expect(resp.body[:order_id]).to eq('123')
    end

    it 'dispatches MQ requests' do
      resp = dispatch('orders.created', body: { user_id: '456' }, transport: :mq)
      expect(resp.status).to eq(200)
      expect(resp.body[:user_id]).to eq('456')
    end
  end

  describe '#dispatch_http' do
    it 'dispatches HTTP requests with method and path' do
      resp = dispatch_http('GET', '/health')
      expect(resp.status).to eq(200)
      expect(resp.body[:status]).to eq('ok')
    end
  end

  describe '#dispatch_mq' do
    it 'dispatches MQ requests' do
      resp = dispatch_mq('orders.created', message: { user_id: '789' })
      expect(resp.status).to eq(200)
      expect(resp.body[:user_id]).to eq('789')
    end

    it 'accepts positional message argument' do
      resp = dispatch_mq('orders.created', { user_id: '790' })
      expect(resp.status).to eq(200)
      expect(resp.body[:user_id]).to eq('790')
    end
  end

  describe '#build_http_request' do
    it 'builds HTTP requests with query params' do
      req = build_http_request('GET', '/orders', query: { page: 2 })
      expect(req.action).to eq('GET:/orders')
      expect(req['page']).to eq(2)
      expect(req.transport).to eq(:http)
    end
  end

  describe '#build_mq_request' do
    it 'builds MQ requests with metadata' do
      req = build_mq_request('orders.created', { user_id: '1' }, metadata: { source: 'spec' })
      expect(req.action).to eq('orders.created')
      expect(req['user_id']).to eq('1')
      expect(req.meta('source')).to eq('spec')
      expect(req.transport).to eq(:mq)
    end
  end

  describe '#build_request' do
    it 'builds HTTP requests' do
      req = build_request('POST:/orders', body: { user_id: '1' })
      expect(req.action).to eq('POST:/orders')
      expect(req.transport).to eq(:http)
    end

    it 'builds MQ requests' do
      req = build_request('orders.created', body: { user_id: '1' }, transport: :mq)
      expect(req.action).to eq('orders.created')
      expect(req.transport).to eq(:mq)
    end
  end

  describe '#build_context' do
    it 'builds a context with defaults' do
      ctx = build_context
      expect(ctx.transport).to eq(:http)
      expect(ctx.auth).to be_nil
    end

    it 'accepts custom values' do
      ctx = build_context(transport: :mq, auth: 'Bearer xyz', request_id: 'req-1')
      expect(ctx.transport).to eq(:mq)
      expect(ctx.auth).to eq('Bearer xyz')
      expect(ctx.request_id).to eq('req-1')
    end
  end

  describe '#fixtures' do
    it 'loads YAML fixtures' do
      data = fixtures(:orders)
      expect(data['valid_order']['user_id']).to eq('user-123')
      expect(data['invalid_order']['items']).to eq([])
    end
  end

  describe '#test_server' do
    it 'dispatches in-memory HTTP requests' do
      server = test_server
      server.route('GET:/ready') { |_req, _ctx| LePain::Response.success({ ready: true }) }

      response = server.get('/ready')

      expect(response).to be_success
      expect(response.body[:ready]).to be true
    end

    it 'handles concurrent requests' do
      server = test_server
      server.route('GET:/counter') { |_req, _ctx| LePain::Response.success({ ok: true }) }

      responses = server.concurrently(count: 20) { |srv| srv.get('/counter') }

      expect(responses.size).to eq(20)
      expect(responses).to all(be_success)
    end
  end

  describe '#mock_mq_client' do
    it 'captures published messages and invokes subscriptions' do
      client = mock_mq_client
      seen = []
      client.subscribe('orders.created') { |message, metadata| seen << [message, metadata] }

      client.publish('orders.created', { user_id: '1' }, metadata: { request_id: 'req-1' })

      expect(client.published.first[:topic]).to eq('orders.created')
      expect(seen.first.first[:user_id]).to eq('1')
      expect(seen.first.last[:request_id]).to eq('req-1')
    end

    it 'can dispatch to a router' do
      router = LePain::Router.new
      router.route('orders.created') { |req, _ctx| LePain::Response.success({ user_id: req['user_id'] }) }
      client = mock_mq_client(router: router)

      response = client.publish('orders.created', { user_id: '2' })

      expect(response.body[:user_id]).to eq('2')
    end
  end

  describe '#with_isolated_task_store' do
    it 'uses an isolated memory task store for the block' do
      original = LePain::AsyncHandler.task_store

      with_isolated_task_store do |store|
        expect(store).not_to eq(original)
        store.create(LePain::Task.new(type: 'spec'))
        expect(store.size).to eq(1)
      end

      expect(LePain::AsyncHandler.task_store).to eq(original)
    end
  end

  describe '#with_context' do
    it 'sets context for the block' do
      with_context(request_id: 'test-1', trace_id: 'trace-1') do |ctx|
        expect(ctx.request_id).to eq('test-1')
        expect(ctx.trace_id).to eq('trace-1')
      end
    end
  end
end

RSpec.describe LePain::Test::Matchers do
  include described_class
  include LePain::Test::Helpers

  let(:success_response) { LePain::Response.success({ id: 1 }, status: 201) }
  let(:error_response) { LePain::Response.error('not found', status: 404) }
  let(:validation_response) do
    LePain::Response.bad_request('Validation failed').tap do |r|
      r.instance_variable_set(:@validation_errors, [{ field: 'user_id', message: 'is required' }])
    end
  end

  describe '#be_success' do
    it { expect(success_response).to be_success }
    it { expect(error_response).not_to be_success }
  end

  describe '#have_status' do
    it { expect(success_response).to have_status(201) }
    it { expect(error_response).to have_status(404) }
    it { expect(success_response).not_to have_status(200) }
  end

  describe '#include_body' do
    it { expect(success_response).to include_body(id: 1) }
    it { expect(success_response).not_to include_body(id: 2) }
  end

  describe '#match_schema' do
    before do
      LePain::Test.reset!
      register_schema(:order, id: Integer)
    end

    it { expect(success_response).to match_schema(:order) }
    it { expect(LePain::Response.success({ id: 'x' })).not_to match_schema(:order) }
  end

  describe '#have_validation_errors' do
    it { expect(validation_response).to have_validation_errors }
    it { expect(validation_response).to have_validation_errors('user_id') }
    it { expect(success_response).not_to have_validation_errors }
  end
end
