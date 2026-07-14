require 'spec_helper'

RSpec.describe LePain::Handler do
  let(:handler_class) do
    Class.new(described_class) do
      handle 'POST:/orders' do |req, ctx|
        LePain::Response.success({ user_id: req['user_id'], transport: ctx.transport }, status: 201)
      end

      handle 'orders.created' do |req, ctx|
        LePain::Response.success({ user_id: req['user_id'], transport: ctx.transport })
      end
    end
  end

  describe '.call' do
    it 'handles HTTP requests' do
      req = LePain::Request.from_http(
        method: 'POST', path: '/orders',
        body: { user_id: '123' },
      )
      ctx = LePain::Context.new(transport: :http)
      resp = handler_class.call(req, context: ctx)

      expect(resp.status).to eq(201)
      expect(resp.body[:user_id]).to eq('123')
      expect(resp.body[:transport]).to eq(:http)
    end

    it 'handles MQ requests' do
      req = LePain::Request.from_mq(
        topic: 'orders.created',
        message: { user_id: '456' },
      )
      ctx = LePain::Context.new(transport: :mq)
      resp = handler_class.call(req, context: ctx)

      expect(resp.status).to eq(200)
      expect(resp.body[:user_id]).to eq('456')
      expect(resp.body[:transport]).to eq(:mq)
    end

    it 'returns 404 for unregistered actions' do
      req = LePain::Request.new(action: 'DELETE:/orders')
      ctx = LePain::Context.new
      resp = handler_class.call(req, context: ctx)

      expect(resp.status).to eq(404)
    end

    it 'returns 500 on handler errors' do
      bad_handler = Class.new(described_class) do
        handle 'boom' do |_req, _ctx|
          raise 'intentional error'
        end
      end

      req = LePain::Request.new(action: 'boom')
      ctx = LePain::Context.new
      resp = bad_handler.call(req, context: ctx)

      expect(resp.status).to eq(500)
    end
  end

  describe 'before_filter' do
    let(:filtered_handler) do
      Class.new(described_class) do
        before_filter do |req, _ctx|
          req['token'] == 'valid' ? nil : LePain::Response.unauthorized
        end

        handle 'POST:/secure' do |_req, _ctx|
          LePain::Response.success({ ok: true })
        end
      end
    end

    it 'blocks invalid requests' do
      req = LePain::Request.new(action: 'POST:/secure', payload: { 'token' => 'bad' })
      ctx = LePain::Context.new
      resp = filtered_handler.call(req, context: ctx)

      expect(resp.status).to eq(401)
    end

    it 'allows valid requests' do
      req = LePain::Request.new(action: 'POST:/secure', payload: { 'token' => 'valid' })
      ctx = LePain::Context.new
      resp = filtered_handler.call(req, context: ctx)

      expect(resp.status).to eq(200)
    end
  end
end
