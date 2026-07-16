require 'spec_helper'
require 'le_pain/health_check'
require 'le_pain/health_check_enhanced'

class FakeHealthClient
  attr_reader :output

  def initialize(request)
    @request = request
    @output = +''
  end

  def gets
    @request
  end

  def print(value)
    @output << value
  end

  def close; end
end

RSpec.describe LePain::HealthCheckEnhanced::Probe do
  let(:probe) { described_class.new(:test) }

  describe '#add_check' do
    it 'adds a check' do
      probe.add_check(:database) { { connected: true } }
      expect(probe.checks.size).to eq(1)
    end
  end

  describe '#run' do
    it 'runs all checks and returns results' do
      probe.add_check(:check1) { { status: 'ok' } }
      probe.add_check(:check2) { { status: 'ok' } }

      result = probe.run
      expect(result[:name]).to eq(:test)
      expect(result[:status]).to eq(:healthy)
      expect(result[:checks].size).to eq(2)
    end

    it 'marks as unhealthy if any check fails' do
      probe.add_check(:check1) { { status: 'ok' } }
      probe.add_check(:check2) { raise 'error' }

      result = probe.run
      expect(result[:status]).to eq(:unhealthy)
    end

    it 'sets last_checked_at' do
      probe.add_check(:check1) { 'ok' }
      probe.run
      expect(probe.last_checked_at).to be_a(Time)
    end
  end

  describe '#healthy?' do
    it 'returns true when healthy' do
      probe.add_check(:check1) { 'ok' }
      probe.run
      expect(probe.healthy?).to be true
    end

    it 'returns false when unhealthy' do
      probe.add_check(:check1) { raise 'error' }
      probe.run
      expect(probe.healthy?).to be false
    end
  end
end

RSpec.describe LePain::HealthCheckEnhanced::EnhancedHealthCheck do
  let(:health_check) { described_class.new }

  describe '#startup' do
    it 'adds startup check' do
      health_check.startup { { initialized: true } }
      expect(health_check.startup_probe.checks.size).to eq(1)
    end
  end

  describe '#readiness' do
    it 'adds readiness check' do
      health_check.readiness(:database) { { connected: true } }
      expect(health_check.readiness_probe.checks.size).to eq(1)
    end

    it 'adds database dependency checks' do
      connection = double('database', exec: true)
      health_check.database(connection)
      health_check.start!

      result = health_check.check_readiness

      expect(result[:status]).to eq(:healthy)
      expect(result[:checks].first[:name]).to eq(:database)
    end

    it 'adds redis dependency checks' do
      redis = double('redis', ping: 'PONG')
      health_check.redis(redis)
      health_check.start!

      expect(health_check.check_readiness[:status]).to eq(:healthy)
    end

    it 'adds mq dependency checks' do
      mq = double('mq', connected?: true)
      health_check.mq(mq)
      health_check.start!

      expect(health_check.check_readiness[:status]).to eq(:healthy)
    end
  end

  describe '#liveness' do
    it 'adds liveness check' do
      health_check.liveness(:process) { { alive: true } }
      expect(health_check.liveness_probe.checks.size).to eq(1)
    end

    it 'adds deadlock liveness checks' do
      health_check.deadlock_check

      result = health_check.check_liveness

      expect(result[:status]).to eq(:healthy)
      expect(result[:checks].first[:name]).to eq(:deadlock)
    end
  end

  describe '#start!' do
    it 'marks service as started' do
      health_check.startup { 'ok' }
      health_check.start!
      expect(health_check.started?).to be true
    end

    it 'runs startup probe' do
      health_check.startup { { initialized: true } }
      health_check.start!
      expect(health_check.startup_probe.last_checked_at).to be_a(Time)
    end
  end

  describe '#check_startup' do
    it 'returns startup probe results' do
      health_check.startup { { initialized: true } }
      result = health_check.check_startup
      expect(result[:name]).to eq(:startup)
    end
  end

  describe '#check_readiness' do
    it 'returns unhealthy if not started' do
      result = health_check.check_readiness
      expect(result[:status]).to eq(:unhealthy)
    end

    it 'returns readiness probe results if started' do
      health_check.readiness { { ready: true } }
      health_check.start!
      result = health_check.check_readiness
      expect(result[:status]).to eq(:healthy)
    end
  end

  describe '#check_liveness' do
    it 'returns liveness probe results' do
      health_check.liveness { { alive: true } }
      result = health_check.check_liveness
      expect(result[:name]).to eq(:liveness)
    end
  end

  describe '#check_all' do
    it 'returns all probe results' do
      health_check.startup { 'ok' }
      health_check.readiness { 'ok' }
      health_check.liveness { 'ok' }
      health_check.start!

      result = health_check.check_all
      expect(result).to have_key(:startup)
      expect(result).to have_key(:readiness)
      expect(result).to have_key(:liveness)
      expect(result).to have_key(:timestamp)
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      health_check.startup { 'ok' }
      health_check.start!
      hash = health_check.to_h
      expect(hash).to be_a(Hash)
    end
  end

  describe '#to_json' do
    it 'returns JSON representation' do
      health_check.startup { 'ok' }
      health_check.start!
      json = health_check.to_json
      expect(JSON.parse(json)).to be_a(Hash)
    end
  end
end

RSpec.describe LePain::HealthCheck do
  let(:enhanced) { LePain::HealthCheckEnhanced::EnhancedHealthCheck.new }
  let(:health_check) { described_class.new(enhanced: enhanced) }

  def response_for(path)
    client = FakeHealthClient.new("GET #{path} HTTP/1.1\r\n")
    health_check.send(:handle_request, client)
    client.output
  end

  it 'serves startup probe endpoint' do
    enhanced.startup { { initialized: true } }

    response = response_for('/health/startup')

    expect(response).to include('HTTP/1.1 200 OK')
    expect(JSON.parse(response.split("\r\n\r\n", 2).last)['name']).to eq('startup')
  end

  it 'serves readiness probe endpoint with 503 when not ready' do
    response = response_for('/health/readiness')

    expect(response).to include('HTTP/1.1 503 Service Unavailable')
    expect(JSON.parse(response.split("\r\n\r\n", 2).last)['status']).to eq('unhealthy')
  end

  it 'serves liveness probe endpoint' do
    enhanced.liveness { { alive: true } }

    response = response_for('/health/liveness')

    expect(response).to include('HTTP/1.1 200 OK')
    expect(JSON.parse(response.split("\r\n\r\n", 2).last)['name']).to eq('liveness')
  end

  it 'serves aggregate health with 503 when a probe is unhealthy' do
    enhanced.startup { { initialized: true } }
    enhanced.readiness { raise 'database down' }
    enhanced.liveness { { alive: true } }
    enhanced.start!

    response = response_for('/health')

    expect(response).to include('HTTP/1.1 503 Service Unavailable')
    expect(JSON.parse(response.split("\r\n\r\n", 2).last)).to include('startup', 'readiness', 'liveness')
  end
end
