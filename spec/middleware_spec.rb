require 'spec_helper'
require 'le_pain/middleware'
require 'brotli'

RSpec.describe LePain::Middleware::Pipeline do
  let(:pipeline) { described_class.new }
  let(:request) { LePain::Request.new(action: 'GET:/test') }
  let(:context) { LePain::Context.new }

  let(:test_middleware) do
    Class.new(LePain::Middleware::Base) do
      def call(request, context, next_handler)
        request.instance_variable_set(:@middleware_ran, true)
        next_handler.call(request, context)
      end
    end
  end

  describe '#register' do
    it 'adds middleware to pipeline' do
      pipeline.register(:test, test_middleware)
      expect(pipeline.names).to eq([:test])
    end
  end

  describe '#insert_before' do
    it 'inserts middleware before target' do
      pipeline.register(:second, test_middleware)
      pipeline.insert_before(:second, :first, test_middleware)
      expect(pipeline.names).to eq([:first, :second])
    end
  end

  describe '#insert_after' do
    it 'inserts middleware after target' do
      pipeline.register(:first, test_middleware)
      pipeline.insert_after(:first, :second, test_middleware)
      expect(pipeline.names).to eq([:first, :second])
    end
  end

  describe '#remove' do
    it 'removes middleware' do
      pipeline.register(:test, test_middleware)
      pipeline.remove(:test)
      expect(pipeline.names).to eq([])
    end
  end

  describe '#execute' do
    it 'executes middlewares in order' do
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

      pipeline.register(:first, first)
      pipeline.register(:second, second)

      handler = ->(req, ctx) { order << :handler; LePain::Response.success({}) }
      pipeline.execute(request, context, &handler)

      expect(order).to eq([:first, :second, :handler])
    end

    it 'allows middleware to short-circuit' do
      blocker = Class.new(LePain::Middleware::Base) do
        define_method(:call) do |req, ctx, next_handler|
          LePain::Response.error('blocked', status: 403)
        end
      end

      pipeline.register(:blocker, blocker)
      handler = ->(req, ctx) { LePain::Response.success({}) }
      response = pipeline.execute(request, context, &handler)

      expect(response.status).to eq(403)
    end

    it 'skips middleware when path condition does not match' do
      pipeline.register(:test, test_middleware, only: { path: '/allowed' })
      handler = ->(req, ctx) { LePain::Response.success({ ran: req.instance_variable_get(:@middleware_ran) }) }

      response = pipeline.execute(LePain::Request.new(action: 'GET:/blocked'), context, &handler)

      expect(response.body[:ran]).to be_nil
    end

    it 'applies middleware by transport and context conditions' do
      context = LePain::Context.new(metadata: { 'role' => 'admin' })
      pipeline.register(
        :test,
        test_middleware,
        only: { transport: :http, context: ->(ctx) { ctx.metadata['role'] == 'admin' } }
      )
      handler = ->(req, ctx) { LePain::Response.success({ ran: req.instance_variable_get(:@middleware_ran) }) }

      response = pipeline.execute(LePain::Request.new(action: 'GET:/test', transport: :http), context, &handler)

      expect(response.body[:ran]).to be true
    end

    it 'excludes middleware when except condition matches' do
      pipeline.register(:test, test_middleware, except: { transport: :mq })
      handler = ->(req, ctx) { LePain::Response.success({ ran: req.instance_variable_get(:@middleware_ran) }) }

      response = pipeline.execute(LePain::Request.new(action: 'topic', transport: :mq), context, &handler)

      expect(response.body[:ran]).to be_nil
    end
  end
end

RSpec.describe LePain::Middleware::RequestId do
  let(:middleware) { described_class.new }
  let(:request) { LePain::Request.new(action: 'GET:/test') }
  let(:context) { LePain::Context.new(request_id: 'req-123') }

  it 'sets request-id header from context' do
    handler = ->(req, ctx) { LePain::Response.success({}) }
    middleware.call(request, context, handler)
    expect(request.headers['x-request-id']).to eq('req-123')
  end

  it 'injects request-id header into response' do
    handler = ->(_req, _ctx) { LePain::Response.success({}) }
    response = middleware.call(request, context, handler)

    expect(response.headers['x-request-id']).to eq('req-123')
  end
end

RSpec.describe LePain::Middleware::Cors do
  let(:middleware) { described_class.new(allowed_origins: ['*']) }
  let(:request) { LePain::Request.new(action: 'GET:/test', headers: { 'origin' => 'http://example.com' }) }
  let(:context) { LePain::Context.new }

  it 'adds CORS headers to response' do
    handler = ->(req, ctx) { LePain::Response.success({}) }
    response = middleware.call(request, context, handler)
    expect(response.headers['Access-Control-Allow-Origin']).to eq('http://example.com')
  end
end

RSpec.describe LePain::Middleware::Compression do
  let(:context) { LePain::Context.new }

  def gzip(value)
    require 'stringio'
    require 'zlib'

    buffer = StringIO.new
    writer = Zlib::GzipWriter.new(buffer)
    writer.write(value)
    writer.close
    buffer.string
  end

  it 'compresses large gzip responses when accepted' do
    middleware = described_class.new(min_size: 10, algorithms: ['gzip'], metrics: false)
    request = LePain::Request.new(action: 'GET:/test', headers: { 'accept-encoding' => 'gzip' })
    handler = ->(_req, _ctx) { LePain::Response.success({ data: 'x' * 100 }) }

    response = middleware.call(request, context, handler)

    expect(response.headers['Content-Encoding']).to eq('gzip')
    expect(response.headers['Vary']).to eq('Accept-Encoding')
    expect(response.compressed_body.bytesize).to eq(response.headers['Content-Length'].to_i)
  end

  it 'compresses large brotli responses when accepted' do
    middleware = described_class.new(min_size: 10, algorithms: ['br'], metrics: false)
    request = LePain::Request.new(action: 'GET:/test', headers: { 'accept-encoding' => 'br' })
    handler = ->(_req, _ctx) { LePain::Response.success({ data: 'x' * 100 }) }

    response = middleware.call(request, context, handler)

    expect(response.headers['Content-Encoding']).to eq('br')
    decompressed = JSON.parse(Brotli.inflate(response.compressed_body))
    expect(decompressed['body']['data']).to eq('x' * 100)
  end

  it 'does not compress small responses' do
    middleware = described_class.new(min_size: 10_000, algorithms: ['gzip'], metrics: false)
    request = LePain::Request.new(action: 'GET:/test', headers: { 'accept-encoding' => 'gzip' })
    handler = ->(_req, _ctx) { LePain::Response.success({ ok: true }) }

    response = middleware.call(request, context, handler)

    expect(response.headers).not_to have_key('Content-Encoding')
    expect(response.compressed_body).to be_nil
  end

  it 'decompresses gzip request bodies before calling the handler' do
    body = JSON.generate({ name: 'baguette' })
    request = LePain::Request.new(
      action: 'POST:/test',
      headers: { 'content-encoding' => 'gzip' },
      raw: gzip(body)
    )
    middleware = described_class.new(algorithms: ['gzip'], metrics: false)
    handler = ->(req, _ctx) { LePain::Response.success(req.payload) }

    response = middleware.call(request, context, handler)

    expect(response.body).to eq({ 'name' => 'baguette' })
    expect(request.headers).not_to have_key('content-encoding')
  end

  it 'decompresses brotli request bodies before calling the handler' do
    body = JSON.generate({ name: 'ficelle' })
    request = LePain::Request.new(
      action: 'POST:/test',
      headers: { 'content-encoding' => 'br' },
      raw: Brotli.deflate(body)
    )
    middleware = described_class.new(algorithms: ['br'], metrics: false)
    handler = ->(req, _ctx) { LePain::Response.success(req.payload) }

    response = middleware.call(request, context, handler)

    expect(response.body).to eq({ 'name' => 'ficelle' })
  end

  it 'rejects unsupported request encodings' do
    request = LePain::Request.new(
      action: 'POST:/test',
      headers: { 'content-encoding' => 'compress' },
      raw: 'payload'
    )
    middleware = described_class.new(algorithms: ['gzip'], metrics: false)
    handler = ->(_req, _ctx) { LePain::Response.success({}) }

    response = middleware.call(request, context, handler)

    expect(response.status).to eq(415)
    expect(response.error[:code]).to eq('unsupported_encoding')
  end

  it 'tracks compression metrics' do
    LePain::Metrics.registry.clear
    middleware = described_class.new(min_size: 10, algorithms: ['gzip'])
    request = LePain::Request.new(action: 'GET:/test', headers: { 'accept-encoding' => 'gzip' })
    handler = ->(_req, _ctx) { LePain::Response.success({ data: 'x' * 100 }) }

    middleware.call(request, context, handler)

    metric = LePain::Metrics.registry.get('compression_bytes_saved_total')
    expect(metric.get({ 'algorithm' => 'gzip' })).to be > 0
  end
end

RSpec.describe LePain::Middleware::RateLimit do
  let(:middleware) { described_class.new(limit: 2, window: 60) }
  let(:request) { LePain::Request.new(action: 'GET:/test', headers: { 'x-forwarded-for' => '1.2.3.4' }) }
  let(:context) { LePain::Context.new }

  it 'allows requests within limit' do
    handler = ->(req, ctx) { LePain::Response.success({}) }
    response = middleware.call(request, context, handler)
    expect(response.status).to eq(200)
    expect(response.headers['X-RateLimit-Remaining']).to eq('1')
  end

  it 'blocks requests over limit' do
    handler = ->(req, ctx) { LePain::Response.success({}) }
    middleware.call(request, context, handler)
    middleware.call(request, context, handler)
    response = middleware.call(request, context, handler)
    expect(response.status).to eq(429)
    expect(response.headers['Retry-After']).to eq('60')
  end
end
