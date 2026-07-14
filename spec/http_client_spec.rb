require 'spec_helper'
require 'stringio'

RSpec.describe LePain::HttpClient do
  class SpecHttpAdapter
    attr_reader :requests

    def initialize(response: nil)
      @response = response || LePain::HttpAdapters::StubAdapter::Response.new(
        code: '200',
        body: '{"ok":true}',
        headers: { 'content-type' => 'application/json' }
      )
      @requests = []
    end

    def execute(request, timeout:, follow_redirects: true)
      @requests << [request, timeout, follow_redirects]
      @response
    end
  end

  describe '#initialize' do
    it 'sets base_url and defaults' do
      client = described_class.new(base_url: 'http://api.example.com')
      expect(client.base_url).to eq('http://api.example.com')
      expect(client.timeout).to eq(5)
      expect(client.max_retries).to eq(0)
    end

    it 'accepts custom options' do
      client = described_class.new(base_url: 'http://api.example.com', timeout: 10, max_retries: 3)
      expect(client.timeout).to eq(10)
      expect(client.max_retries).to eq(3)
    end

    it 'uses net_http adapter by default' do
      client = described_class.new(base_url: 'http://api.example.com')
      expect(client.adapter).to be_a(LePain::HttpAdapters::NetHttpAdapter)
    end
  end

  describe '.register_adapter' do
    after do
      described_class.adapters.delete(:spec)
    end

    it 'registers custom client adapters' do
      described_class.register_adapter(:spec, SpecHttpAdapter)
      client = described_class.new(base_url: 'http://api.example.com', adapter: :spec)

      response = client.get('/ok')

      expect(response.success?).to be true
      expect(client.adapter.requests.first.first.path).to eq('/ok')
    end
  end

  describe '.for' do
    it 'builds a named service client from config' do
      config = {
        'http_client' => {
          'default_timeout' => 2,
          'max_retries' => 1,
          'adapter' => 'stub',
          'services' => {
            'order-service' => {
              'base_url' => 'http://orders.local',
              'timeout' => 7,
              'retries' => 3,
            },
          },
        },
      }

      client = described_class.for(:order_service, config: config)

      expect(client.base_url).to eq('http://orders.local')
      expect(client.timeout).to eq(7)
      expect(client.max_retries).to eq(3)
      expect(client.adapter).to be_a(LePain::HttpAdapters::StubAdapter)
    end
  end

  describe 'context propagation' do
    it 'builds correct headers from context' do
      client = described_class.new(base_url: 'http://api.example.com')
      ctx = LePain::Context.new(
        request_id: 'req-1',
        trace_id: 'trace-1',
        correlation_id: 'corr-1',
        auth: 'Bearer token',
      )

      LePain::Context.with(ctx) do
        req = Net::HTTP::Get.new(URI('http://api.example.com/test'))
        client.send(:inject_headers, req, {})

        expect(req['x-request-id']).to eq('req-1')
        expect(req['x-trace-id']).to eq('trace-1')
        expect(req['x-correlation-id']).to eq('corr-1')
        expect(req['authorization']).to eq('Bearer token')
      end
    end

    it 'forwards idempotency key from context' do
      client = described_class.new(base_url: 'http://api.example.com')
      ctx = LePain::Context.new(idempotency_key: 'idem-1')

      LePain::Context.with(ctx) do
        req = Net::HTTP::Post.new(URI('http://api.example.com/orders'))
        client.send(:inject_headers, req, {})

        expect(req['idempotency-key']).to eq('idem-1')
      end
    end

    it 'generates idempotency keys for retryable mutating requests' do
      adapter = LePain::HttpAdapters::StubAdapter.new(responses: { '/orders' => { status: 201, body: { ok: true } } })
      client = described_class.new(base_url: 'http://api.example.com', adapter: adapter, max_retries: 1)

      client.post('/orders', body: { user_id: '123' })

      expect(adapter.requests.first['idempotency-key']).not_to be_nil
    end

    it 'adds default headers' do
      client = described_class.new(base_url: 'http://api.example.com', default_headers: { 'X-Api-Key' => 'secret' })
      req = Net::HTTP::Get.new(URI('http://api.example.com/test'))
      client.send(:inject_headers, req, {})

      expect(req['x-api-key']).to eq('secret')
    end

    it 'extra headers override defaults' do
      client = described_class.new(base_url: 'http://api.example.com', default_headers: { 'X-Api-Key' => 'default' })
      req = Net::HTTP::Get.new(URI('http://api.example.com/test'))
      client.send(:inject_headers, req, { 'X-Api-Key' => 'override' })

      expect(req['x-api-key']).to eq('override')
    end
  end

  describe 'adapters' do
    it 'uses stub adapter responses' do
      adapter = LePain::HttpAdapters::StubAdapter.new(
        responses: { 'GET /users/1' => { status: 200, body: { id: 1 }, headers: { 'x-test' => 'ok' } } }
      )
      client = described_class.new(base_url: 'http://api.example.com', adapter: adapter)

      response = client.get('/users/1')

      expect(response.status).to eq(200)
      expect(response['id']).to eq(1)
      expect(response.header('x-test')).to eq('ok')
    end
  end

  describe 'resilience' do
    it 'retries transient HTTP statuses' do
      adapter = LePain::HttpAdapters::StubAdapter.new(
        responses: {
          '/orders' => [
            { status: 503, body: { error: 'busy' } },
            { status: 200, body: { ok: true } },
          ],
        }
      )
      client = described_class.new(
        base_url: 'http://api.example.com',
        adapter: adapter,
        max_retries: 1,
        retry_base_delay: 0
      )

      response = client.get('/orders')

      expect(response.status).to eq(200)
      expect(adapter.requests.size).to eq(2)
    end

    it 'uses circuit breaker when configured' do
      failing_adapter = Class.new do
        def execute(request, timeout:, follow_redirects: true)
          raise Errno::ECONNREFUSED
        end
      end.new
      breaker = LePain::CircuitBreaker.new(name: 'http-spec', failure_threshold: 1)
      client = described_class.new(base_url: 'http://api.example.com', adapter: failing_adapter, circuit_breaker: breaker)

      expect { client.get('/down') }.to raise_error(Errno::ECONNREFUSED)
      expect { client.get('/down') }.to raise_error(LePain::CircuitOpenError)
    end

    it 'logs requests and responses' do
      io = StringIO.new
      logger = LePain::Logging.build_logger(format: :json, output: io)
      adapter = LePain::HttpAdapters::StubAdapter.new(responses: { '/ok' => { status: 200, body: { ok: true } } })
      client = described_class.new(base_url: 'http://api.example.com', adapter: adapter, logger: logger)

      client.get('/ok')

      messages = io.string.lines.map { |line| JSON.parse(line)['message'] }
      expect(messages).to include('http client request', 'http client response')
    end
  end
end

RSpec.describe LePain::HttpResponse do
  let(:net_response) do
    double(code: '200', body: '{"status":"ok","id":1}', to_hash: { 'content-type' => ['application/json'], 'x-request-id' => ['req-1'] })
  end

  describe '#success?' do
    it 'returns true for 2xx status' do
      resp = described_class.new(net_response)
      expect(resp.success?).to be true
    end

    it 'returns false for non-2xx status' do
      err_response = double(code: '500', body: '{"error":"fail"}', to_hash: {})
      resp = described_class.new(err_response)
      expect(resp.success?).to be false
    end
  end

  describe '#[]' do
    it 'accesses body by key' do
      resp = described_class.new(net_response)
      expect(resp['status']).to eq('ok')
      expect(resp['id']).to eq(1)
    end
  end

  describe '#header' do
    it 'returns response headers' do
      resp = described_class.new(net_response)
      expect(resp.header('content-type')).to eq('application/json')
      expect(resp.header('x-request-id')).to eq('req-1')
    end
  end

  describe '#status' do
    it 'returns integer status code' do
      resp = described_class.new(net_response)
      expect(resp.status).to eq(200)
    end
  end

  describe 'empty body' do
    it 'handles nil body' do
      empty_response = double(code: '204', body: nil, to_hash: {})
      resp = described_class.new(empty_response)
      expect(resp.body).to eq({})
    end
  end
end
