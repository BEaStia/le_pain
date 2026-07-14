require 'spec_helper'
require 'stringio'

RSpec.describe LePain::Logging do
  describe '.build_logger' do
    it 'creates a logger with default settings' do
      logger = described_class.build_logger
      expect(logger).to be_a(Logger)
      expect(logger.level).to eq(Logger::INFO)
    end

    it 'respects level config' do
      logger = described_class.build_logger(level: :debug)
      expect(logger.level).to eq(Logger::DEBUG)
    end

    it 'supports per-transport log levels' do
      logger = described_class.build_logger(level: :info, transport_levels: { mq: :debug })
      expect(logger.level).to eq(Logger::DEBUG)
      expect(logger.transport_levels[:mq]).to eq(Logger::DEBUG)
    end

    it 'respects format config for json' do
      logger = described_class.build_logger(format: :json)
      expect(logger.formatter).to be_a(LePain::Logging::JsonFormatter)
    end

    it 'respects format config for text' do
      logger = described_class.build_logger(format: :text)
      expect(logger.formatter).to be_a(Proc)
    end
  end

  describe '.build_formatter' do
    it 'returns JsonFormatter for :json' do
      formatter = described_class.build_formatter(:json)
      expect(formatter).to be_a(LePain::Logging::JsonFormatter)
    end

    it 'returns Proc for :text' do
      formatter = described_class.build_formatter(:text)
      expect(formatter).to be_a(Proc)
    end
  end

  describe '.resolve_output' do
    it 'returns STDOUT for stdout' do
      expect(described_class.resolve_output('stdout')).to eq(STDOUT)
    end

    it 'returns STDERR for stderr' do
      expect(described_class.resolve_output('stderr')).to eq(STDERR)
    end
  end

  describe LePain::Logging::StructuredLogger do
    it 'accepts extra fields as keyword arguments' do
      io = StringIO.new
      logger = LePain::Logging.build_logger(format: :json, output: io)

      logger.info('hello', extra: { duration_ms: 12 }, component: 'spec')

      parsed = JSON.parse(io.string)
      expect(parsed['message']).to eq('hello')
      expect(parsed['duration_ms']).to eq(12)
      expect(parsed['component']).to eq('spec')
    end

    it 'filters messages below the current transport level' do
      io = StringIO.new
      logger = LePain::Logging.build_logger(
        format: :json,
        output: io,
        level: :info,
        transport_levels: { mq: :debug, http: :warn }
      )

      LePain::Context.with(LePain::Context.new(transport: :http)) { logger.info('http info') }
      LePain::Context.with(LePain::Context.new(transport: :mq)) { logger.debug('mq debug') }

      lines = io.string.lines.map { |line| JSON.parse(line) }
      expect(lines.map { |line| line['message'] }).to eq(['mq debug'])
    end
  end
end

RSpec.describe LePain::Logging::JsonFormatter do
  let(:formatter) { described_class.new }
  let(:datetime) { Time.now }

  it 'produces valid JSON' do
    line = formatter.call('INFO', datetime, nil, 'test message')
    parsed = JSON.parse(line)
    expect(parsed['message']).to eq('test message')
    expect(parsed['level']).to eq('info')
    expect(parsed['timestamp']).to be_a(String)
  end

  it 'includes context fields when available' do
    ctx = LePain::Context.new(request_id: 'req-1', trace_id: 'trace-1', transport: :http)
    LePain::Context.with(ctx) do
      line = formatter.call('INFO', datetime, nil, 'test')
      parsed = JSON.parse(line)
      expect(parsed['request_id']).to eq('req-1')
      expect(parsed['trace_id']).to eq('trace-1')
      expect(parsed['transport']).to eq('http')
    end
  end

  it 'merges extra fields' do
    line = formatter.call('INFO', datetime, nil, { message: 'test', extra: { duration_ms: 42 } })
    parsed = JSON.parse(line)
    expect(parsed['message']).to eq('test')
    expect(parsed['duration_ms']).to eq(42)
  end

  it 'handles plain string messages' do
    line = formatter.call('ERROR', datetime, nil, 'something broke')
    parsed = JSON.parse(line)
    expect(parsed['message']).to eq('something broke')
    expect(parsed['level']).to eq('error')
  end
end

RSpec.describe 'request/response structured logging' do
  after do
    LePain::Application.instance_variable_set(:@logger, nil)
  end

  it 'logs request and response events with masked bodies' do
    io = StringIO.new
    logger = LePain::Logging.build_logger(format: :json, output: io)
    LePain::Application.instance_variable_set(:@logger, logger)

    router = LePain::Router.new
    router.configure_request_logging(enabled: true, log_body: true, sensitive_fields: %w[password])
    router.route('POST:/login') { |_req, _ctx| LePain::Response.success({ ok: true, password: 'secret' }) }

    request = LePain::Request.new(
      action: 'POST:/login',
      payload: { email: 'user@example.com', password: 'secret' },
      transport: :http
    )
    router.dispatch(request, context: LePain::Context.new(request_id: 'req-log', transport: :http))

    entries = io.string.lines.map { |line| JSON.parse(line) }
    request_log = entries.find { |entry| entry['event'] == 'request' }
    response_log = entries.find { |entry| entry['event'] == 'response' }

    expect(request_log['request_id']).to eq('req-log')
    expect(request_log['method']).to eq('POST')
    expect(request_log['path']).to eq('/login')
    expect(request_log['body']['password']).to eq('[FILTERED]')
    expect(response_log['status']).to eq(200)
    expect(response_log['duration_ms']).to be_a(Numeric)
    expect(response_log['body']['password']).to eq('[FILTERED]')
  end
end
