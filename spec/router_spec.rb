require 'spec_helper'

RSpec.describe LePain::Router do
  let(:router) { described_class.new }

  describe '#register / #dispatch' do
    it 'dispatches to registered handler class' do
      handler = Class.new(LePain::Handler) do
        handle 'POST:/orders' do |_req, ctx|
          LePain::Response.success({ id: 1 }, status: 201)
        end
      end

      router.register('POST:/orders', handler)
      req = LePain::Request.from_http(method: 'POST', path: '/orders', body: {})
      resp = router.dispatch(req)

      expect(resp.status).to eq(201)
      expect(resp.body).to eq({ id: 1 })
    end

    it 'dispatches to inline handler' do
      router.route('health') do |_req, ctx|
        LePain::Response.success({ status: 'ok' })
      end

      req = LePain::Request.new(action: 'health')
      resp = router.dispatch(req)

      expect(resp.status).to eq(200)
    end

    it 'returns 404 for unregistered actions' do
      req = LePain::Request.new(action: 'missing')
      resp = router.dispatch(req)

      expect(resp.status).to eq(404)
    end
  end

  describe 'path parameter routing' do
    it 'matches patterns like GET:/jobs/:id' do
      router.route('GET:/jobs/:id') do |req, _ctx|
        LePain::Response.success({ 'id' => req['id'] })
      end

      req = LePain::Request.new(action: 'GET:/jobs/abc-123')
      resp = router.dispatch(req)

      expect(resp.status).to eq(200)
      expect(resp.body['id']).to eq('abc-123')
    end
  end

  describe 'middleware' do
    it 'runs middlewares before handler' do
      router.use do |req, _ctx|
        req.instance_variable_set(:@middleware_ran, true)
        nil
      end

      router.route('test') do |req, _ctx|
        LePain::Response.success({ ran: req.instance_variable_get(:@middleware_ran) })
      end

      req = LePain::Request.new(action: 'test')
      resp = router.dispatch(req)

      expect(resp.body[:ran]).to be true
    end

    it 'can short-circuit with a response' do
      router.use do |_req, _ctx|
        LePain::Response.error('blocked', status: 403)
      end

      router.route('test') do |_req, _ctx|
        LePain::Response.success({})
      end

      req = LePain::Request.new(action: 'test')
      resp = router.dispatch(req)

      expect(resp.status).to eq(403)
    end

    it 'registers class middleware with defined ordering' do
      order = []
      first = Class.new(LePain::Middleware::Base) do
        define_method(:call) do |req, ctx, next_handler|
          order << :first
          next_handler.call(req, ctx)
        end
      end
      second = Class.new(LePain::Middleware::Base) do
        define_method(:call) do |req, ctx, next_handler|
          order << :second
          next_handler.call(req, ctx)
        end
      end

      router.middleware(:second, second)
      router.middleware(:first, first, before: :second)
      router.route('test') do |_req, _ctx|
        order << :handler
        LePain::Response.success({})
      end

      router.dispatch(LePain::Request.new(action: 'test'))

      expect(router.middleware_names).to eq(%i[first second])
      expect(order).to eq(%i[first second handler])
    end

    it 'skips class middleware when conditions do not match' do
      marker = Class.new(LePain::Middleware::Base) do
        def call(request, context, next_handler)
          request.payload['ran'] = true
          next_handler.call(request, context)
        end
      end

      router.middleware(:marker, marker, only: { path: '/allowed', transport: :http })
      router.route('GET:/allowed') { |req, _ctx| LePain::Response.success({ ran: req['ran'] || false }) }
      router.route('GET:/blocked') { |req, _ctx| LePain::Response.success({ ran: req['ran'] || false }) }

      allowed = router.dispatch(LePain::Request.new(action: 'GET:/allowed', transport: :http))
      blocked = router.dispatch(LePain::Request.new(action: 'GET:/blocked', transport: :http))
      mq = router.dispatch(LePain::Request.new(action: 'GET:/allowed', transport: :mq))

      expect(allowed.body[:ran]).to be true
      expect(blocked.body[:ran]).to be false
      expect(mq.body[:ran]).to be false
    end

    it 'supports built-in request-id middleware through router middleware API' do
      router.middleware(:request_id, LePain::Middleware::RequestId)
      router.route('test') { |_req, _ctx| LePain::Response.success({}) }

      response = router.dispatch(LePain::Request.new(action: 'test'), context: LePain::Context.new(request_id: 'req-router'))

      expect(response.headers['x-request-id']).to eq('req-router')
    end

    it 'loads middleware from config' do
      router.load_middleware_config(
        'middleware' => [
          { 'name' => 'request_id' },
          {
            'name' => 'cors',
            'only' => { 'transport' => 'http' },
            'options' => { 'allowed_origins' => ['https://example.test'] },
          },
        ]
      )
      router.route('GET:/test') { |_req, _ctx| LePain::Response.success({}) }

      response = router.dispatch(
        LePain::Request.new(
          action: 'GET:/test',
          transport: :http,
          headers: { 'origin' => 'https://example.test' }
        ),
        context: LePain::Context.new(request_id: 'req-config')
      )

      expect(router.middleware_names).to eq(%i[request_id cors])
      expect(response.headers['x-request-id']).to eq('req-config')
      expect(response.headers['Access-Control-Allow-Origin']).to eq('https://example.test')
    end
  end

  describe 'idempotency' do
    it 'caches successful responses' do
      call_count = 0
      router.idempotency(ttl: 60)
      router.route('POST:/orders') do |_req, _ctx|
        call_count += 1
        LePain::Response.success({ id: call_count })
      end

      req = LePain::Request.new(action: 'POST:/orders', payload: {}, metadata: {}, headers: { 'idempotency-key' => 'idem-1' })

      resp1 = router.dispatch(req)
      resp2 = router.dispatch(req)

      expect(resp1.body[:id]).to eq(1)
      expect(resp2.body[:id]).to eq(1)
      expect(call_count).to eq(1)
    end

    it 'does not cache error responses' do
      call_count = 0
      router.idempotency(ttl: 60)
      router.route('POST:/orders') do |_req, _ctx|
        call_count += 1
        LePain::Response.error('fail')
      end

      req = LePain::Request.new(action: 'POST:/orders', payload: {}, metadata: {}, headers: { 'idempotency-key' => 'idem-2' })

      router.dispatch(req)
      router.dispatch(req)

      expect(call_count).to eq(2)
    end
  end

  describe 'auth extraction' do
    it 'uses default auth header' do
      router.route('test') do |_req, ctx|
        LePain::Response.success({ auth: ctx.auth })
      end

      req = LePain::Request.new(action: 'test', headers: { 'authorization' => 'Bearer xyz' })
      resp = router.dispatch(req)

      expect(resp.body[:auth]).to eq('Bearer xyz')
    end

    it 'supports custom auth header' do
      router.auth_header('X-Api-Key')
      router.route('test') do |_req, ctx|
        LePain::Response.success({ auth: ctx.auth })
      end

      req = LePain::Request.new(action: 'test', headers: { 'x-api-key' => 'secret' })
      resp = router.dispatch(req)

      expect(resp.body[:auth]).to eq('secret')
    end

    it 'supports multiple auth headers' do
      router.auth_headers('X-Api-Key', 'Authorization')
      router.route('test') do |_req, ctx|
        LePain::Response.success({ auth: ctx.auth })
      end

      req = LePain::Request.new(action: 'test', headers: { 'x-api-key' => 'key-123' })
      resp = router.dispatch(req)

      expect(resp.body[:auth]).to eq('key-123')
    end
  end

  describe 'request/response transformations' do
    it 'applies request transformers before the handler' do
      router.transform_request do |req|
        req.payload['quantity'] = req.payload['quantity'].to_i
      end

      router.route('POST:/orders') do |req, _ctx|
        LePain::Response.success({ quantity: req['quantity'] })
      end

      req = LePain::Request.new(action: 'POST:/orders', payload: { quantity: '2' })
      resp = router.dispatch(req)

      expect(resp.body[:quantity]).to eq(2)
    end

    it 'applies response transformers after the handler' do
      router.transform_response do |resp|
        resp.body['api_version'] = 'v2'
      end

      router.route('GET:/orders') do |_req, _ctx|
        LePain::Response.success({ 'orders' => [] })
      end

      req = LePain::Request.new(action: 'GET:/orders')
      resp = router.dispatch(req)

      expect(resp.body['api_version']).to eq('v2')
    end

    it 'chains transformers in registration order' do
      router.transform_request { |req| req.payload['steps'] = ['first'] }
      router.transform_request { |req| req.payload['steps'] << 'second' }

      router.route('POST:/chain') do |req, _ctx|
        LePain::Response.success({ steps: req['steps'] })
      end

      resp = router.dispatch(LePain::Request.new(action: 'POST:/chain'))

      expect(resp.body[:steps]).to eq(%w[first second])
    end

    it 'applies transformers by path pattern and transport' do
      router.transform_request(path: '/orders/:id', transport: :http) do |req|
        req.payload['matched'] = true
      end

      router.route('GET:/orders/:id') do |req, _ctx|
        LePain::Response.success({ matched: req['matched'] || false })
      end

      http_req = LePain::Request.new(action: 'GET:/orders/123', transport: :http)
      mq_req = LePain::Request.new(action: 'GET:/orders/123', transport: :mq)

      expect(router.dispatch(http_req).body[:matched]).to be true
      expect(router.dispatch(mq_req).body[:matched]).to be false
    end

    it 'applies response transformers by content type' do
      router.transform_response(content_type: 'application/json') do |resp|
        resp.body['json'] = true
      end

      router.route('GET:/json') do |_req, _ctx|
        LePain::Response.new(body: {}, headers: { 'Content-Type' => 'application/json; charset=utf-8' })
      end

      router.route('GET:/text') do |_req, _ctx|
        LePain::Response.new(body: {}, headers: { 'Content-Type' => 'text/plain' })
      end

      expect(router.dispatch(LePain::Request.new(action: 'GET:/json')).body['json']).to be true
      expect(router.dispatch(LePain::Request.new(action: 'GET:/text')).body['json']).to be_nil
    end

    it 'supports built-in transformers' do
      router.transform_request(transformer: LePain::Transformers.camel_to_snake)
      router.transform_response(transformer: LePain::Transformers.snake_to_camel)
      router.transform_response(transformer: LePain::Transformers.mask_fields(:password_hash))
      router.transform_response(transformer: LePain::Transformers.remove_null_fields)
      router.transform_response(transformer: LePain::Transformers.add_timestamps(clock: -> { Time.utc(2026, 7, 14, 12, 0, 0) }))

      router.route('POST:/users') do |req, _ctx|
        LePain::Response.success({
          'user_id' => req['user_id'],
          'password_hash' => 'secret',
          'empty' => nil,
        })
      end

      req = LePain::Request.new(action: 'POST:/users', payload: { 'userId' => 'u-1' })
      resp = router.dispatch(req)

      expect(resp.body['userId']).to eq('u-1')
      expect(resp.body['passwordHash']).to eq('[FILTERED]')
      expect(resp.body).not_to have_key('empty')
      expect(resp.body['timestamp']).to eq('2026-07-14T12:00:00Z')
    end
  end
end
