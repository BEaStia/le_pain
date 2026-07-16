require 'spec_helper'
require 'le_pain/security'
require 'le_pain/transports/http'

RSpec.describe LePain::Security::SecurityHeaders do
  let(:middleware) { described_class.new }
  let(:request) { LePain::Request.new(action: 'GET:/test') }
  let(:context) { LePain::Context.new }
  let(:handler) { ->(req, ctx) { LePain::Response.success({}) } }

  it 'adds security headers to response' do
    response = middleware.call(request, context, handler)
    expect(response.headers['X-Frame-Options']).to eq('DENY')
    expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    expect(response.headers['X-XSS-Protection']).to eq('1; mode=block')
    expect(response.headers['Strict-Transport-Security']).to include('max-age=')
    expect(response.headers['Content-Security-Policy']).to include("default-src")
    expect(response.headers['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
  end
end

RSpec.describe LePain::Security::PayloadLimit do
  let(:middleware) { described_class.new(max_size: 100) }
  let(:context) { LePain::Context.new }
  let(:handler) { ->(req, ctx) { LePain::Response.success({}) } }

  it 'allows small payloads' do
    request = LePain::Request.new(action: 'POST:/test', headers: { 'content-length' => '50' })
    response = middleware.call(request, context, handler)
    expect(response.status).to eq(200)
  end

  it 'rejects large payloads' do
    request = LePain::Request.new(action: 'POST:/test', headers: { 'content-length' => '200' })
    response = middleware.call(request, context, handler)
    expect(response.status).to eq(413)
    expect(response.error[:message]).to include('too large')
  end

  it 'rejects disallowed content types' do
    middleware = described_class.new(allowed_types: ['application/json'])
    request = LePain::Request.new(action: 'POST:/test', headers: { 'content-type' => 'text/plain' })

    response = middleware.call(request, context, handler)

    expect(response.status).to eq(415)
    expect(response.error[:code]).to eq('unsupported_content_type')
  end
end

RSpec.describe LePain::Security::InputSanitizer do
  let(:middleware) { described_class.new(max_string_length: 10) }
  let(:context) { LePain::Context.new }
  let(:handler) { ->(req, ctx) { LePain::Response.success({ value: req['input'] }) } }

  it 'strips null bytes' do
    request = LePain::Request.new(action: 'POST:/test', payload: { 'input' => "hello\0world" })
    response = middleware.call(request, context, handler)
    expect(response.body[:value]).to eq('helloworld')
  end

  it 'truncates long strings' do
    request = LePain::Request.new(action: 'POST:/test', payload: { 'input' => 'a' * 20 })
    response = middleware.call(request, context, handler)
    expect(response.body[:value].length).to eq(10)
  end

  it 'sanitizes nested structures' do
    request = LePain::Request.new(action: 'POST:/test', payload: {
      'nested' => { 'value' => "test\0data" },
      'array' => ["item\0one", "item\0two"]
    })
    middleware.call(request, context, handler)
    expect(request.payload['nested']['value']).to eq('testdata')
    expect(request.payload['array']).to eq(['itemone', 'itemtwo'])
  end

  it 'escapes xss-sensitive characters' do
    request = LePain::Request.new(action: 'POST:/test', payload: { 'input' => '<script>alert("x")</script>' })
    response = middleware.call(request, context, handler)

    expect(response.body[:value]).to eq('&lt;script')
  end

  it 'rejects sql injection patterns' do
    request = LePain::Request.new(action: 'POST:/test', payload: { 'input' => "1; DROP TABLE users" })
    response = middleware.call(request, context, handler)

    expect(response.status).to eq(400)
    expect(response.error[:code]).to eq('sql_injection')
  end

  it 'rejects path traversal patterns' do
    request = LePain::Request.new(action: 'POST:/test', payload: { 'input' => '../config/secrets.yml' })
    response = middleware.call(request, context, handler)

    expect(response.status).to eq(400)
    expect(response.error[:code]).to eq('path_traversal')
  end
end

RSpec.describe LePain::Security::AuditLog do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil) }
  let(:middleware) { described_class.new(logger: logger) }
  let(:request) { LePain::Request.new(action: 'POST:/test') }
  let(:context) { LePain::Context.new(request_id: 'req-1', trace_id: 'trace-1') }

  it 'logs successful requests' do
    handler = ->(req, ctx) { LePain::Response.success({}) }
    middleware.call(request, context, handler)
    expect(logger).to have_received(:info).with(/SECURITY_AUDIT/)
  end

  it 'logs failed requests as warnings' do
    handler = ->(req, ctx) { LePain::Response.error('error', status: 500) }
    middleware.call(request, context, handler)
    expect(logger).to have_received(:warn).with(/SECURITY_AUDIT/)
  end

  it 'chains audit entries with tamper-evident hashes' do
    messages = []
    logger = instance_double(Logger, info: nil, warn: nil, error: nil)
    allow(logger).to receive(:info) { |message| messages << message }
    middleware = described_class.new(logger: logger)
    handler = ->(_req, _ctx) { LePain::Response.success({}) }

    middleware.call(request, context, handler)
    middleware.call(request, context, handler)

    first = JSON.parse(messages[0].sub('SECURITY_AUDIT: ', ''))
    second = JSON.parse(messages[1].sub('SECURITY_AUDIT: ', ''))
    expect(first['hash']).to match(/\A[0-9a-f]{64}\z/)
    expect(second['previous_hash']).to eq(first['hash'])
  end

  it 'classifies auth failures' do
    messages = []
    logger = instance_double(Logger, info: nil, warn: nil, error: nil)
    allow(logger).to receive(:warn) { |message| messages << message }
    middleware = described_class.new(logger: logger)
    handler = ->(_req, _ctx) { LePain::Response.unauthorized }

    middleware.call(request, context, handler)

    entry = JSON.parse(messages.first.sub('SECURITY_AUDIT: ', ''))
    expect(entry['event']).to eq('auth_failure')
  end
end

RSpec.describe LePain::Security do
  around do |example|
    old_value = ENV['LEPAIN_SPEC_SECRET']
    ENV['LEPAIN_SPEC_SECRET'] = 'resolved-secret'
    example.run
  ensure
    ENV['LEPAIN_SPEC_SECRET'] = old_value
    described_class.reset_secret_providers!
  end

  it 'resolves environment placeholders in config hashes' do
    config = described_class.resolve_secrets(
      'token' => '${LEPAIN_SPEC_SECRET}',
      'fallback' => '${LEPAIN_MISSING_SECRET:-fallback-value}',
      'nested' => ['env:LEPAIN_SPEC_SECRET']
    )

    expect(config['token']).to eq('resolved-secret')
    expect(config['fallback']).to eq('fallback-value')
    expect(config['nested']).to eq(['resolved-secret'])
  end

  it 'resolves vault references through registered providers' do
    provider = Class.new do
      def fetch(path, key: nil)
        "#{path}:#{key}"
      end
    end.new
    described_class.register_secret_provider('vault', provider)

    expect(described_class.resolve_secrets('vault:secret/data/app#token')).to eq('secret/data/app:token')
  end
end

RSpec.describe LePain::Security::AwsSecretsManagerProvider do
  it 'extracts keys from json secret strings' do
    client = Class.new do
      Response = Struct.new(:secret_string, keyword_init: true)

      def get_secret_value(secret_id:)
        Response.new(secret_string: JSON.generate('password' => "#{secret_id}-value"))
      end
    end.new

    provider = described_class.new(client: client)

    expect(provider.fetch('prod/app', key: 'password')).to eq('prod/app-value')
  end
end

RSpec.describe 'security application integration' do
  it 'loads security middleware from config' do
    router = LePain::Router.new
    allow(LePain::Application).to receive(:config).and_return(
      'security' => {
        'enabled' => true,
        'headers' => { 'x_frame_options' => 'SAMEORIGIN' },
        'payload' => { 'max_size' => 128 },
        'sanitizer' => { 'max_string_length' => 20 },
        'audit' => {},
      }
    )

    LePain::Application.configure_security_middleware(router)

    expect(router.middleware_names).to include(
      :security_payload_limit,
      :security_input_sanitizer,
      :security_audit_log,
      :security_headers
    )
  end

  it 'keeps tls configuration on the http adapter' do
    adapter = LePain::Transports::HttpAdapter.new(
      router: LePain::Router.new,
      host: '127.0.0.1',
      port: 3443,
      tls: { 'enabled' => true, 'cert' => '/tmp/cert.pem', 'key' => '/tmp/key.pem', 'min_version' => 'TLS1_3' }
    )

    expect(adapter.host).to eq('127.0.0.1')
    expect(adapter.tls['enabled']).to be true
    expect(adapter.tls['min_version']).to eq('TLS1_3')
  end
end
