require 'spec_helper'
require 'le_pain/security'

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
end
