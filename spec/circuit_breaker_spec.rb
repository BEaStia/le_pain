require 'spec_helper'
require 'le_pain/circuit_breaker'
require 'le_pain/transports'
require 'le_pain/transports/mq'
require 'le_pain/transports/mq_clients'

RSpec.describe LePain::CircuitBreaker do
  let(:breaker) { described_class.new(name: 'test', failure_threshold: 3, success_threshold: 2, timeout: 1) }

  before do
    described_class.clear
    LePain::Metrics.instance_variable_set(:@registry, nil)
  end

  describe '#initialize' do
    it 'starts in closed state' do
      expect(breaker).to be_closed
      expect(breaker.failure_count).to eq(0)
    end
  end

  describe '#call' do
    it 'executes block and returns result' do
      result = breaker.call { 'success' }
      expect(result).to eq('success')
    end

    it 'records success' do
      breaker.call { 'ok' }
      expect(breaker.success_count).to eq(1)
      expect(breaker.failure_count).to eq(0)
    end

    it 'records failure' do
      expect { breaker.call { raise 'error' } }.to raise_error('error')
      expect(breaker.failure_count).to eq(1)
      expect(breaker.success_count).to eq(0)
    end
  end

  describe 'state transitions' do
    context 'closed -> open' do
      it 'opens after failure_threshold failures' do
        3.times { breaker.call { raise 'error' } rescue nil }
        expect(breaker).to be_open
      end

      it 'raises CircuitOpenError when open' do
        3.times { breaker.call { raise 'error' } rescue nil }
        expect { breaker.call { 'ok' } }.to raise_error(LePain::CircuitOpenError)
      end
    end

    context 'open -> half_open' do
      before do
        3.times { breaker.call { raise 'error' } rescue nil }
        expect(breaker).to be_open
        sleep 1.1 # timeout
      end

      it 'transitions to half_open after timeout' do
        breaker.call { 'ok' }
        expect(breaker).to be_half_open
      end
    end

    context 'half_open -> closed' do
      before do
        3.times { breaker.call { raise 'error' } rescue nil }
        sleep 1.1
        breaker.call { 'ok' }
        expect(breaker).to be_half_open
      end

      it 'closes after success_threshold successes' do
        breaker.call { 'ok' }
        expect(breaker).to be_closed
      end
    end

    context 'half_open -> open' do
      before do
        3.times { breaker.call { raise 'error' } rescue nil }
        sleep 1.1
        breaker.call { 'ok' }
        expect(breaker).to be_half_open
      end

      it 'opens on failure' do
        expect { breaker.call { raise 'error' } }.to raise_error('error')
        expect(breaker).to be_open
      end
    end
  end

  describe '#reset' do
    it 'resets to closed state' do
      3.times { breaker.call { raise 'error' } rescue nil }
      expect(breaker).to be_open
      breaker.reset
      expect(breaker).to be_closed
      expect(breaker.failure_count).to eq(0)
    end
  end

  describe '.get / .register / .configure' do
    it 'returns named singleton breakers' do
      first = described_class.get('redis')
      second = described_class.get('redis')

      expect(first).to eq(second)
      expect(first.name).to eq('redis')
    end

    it 'configures breakers from hashes' do
      described_class.configure(
        'redis' => {
          'failure_threshold' => 1,
          'success_threshold' => 1,
          'timeout' => 0.01,
        }
      )

      configured = described_class.get('redis')
      configured.call { raise 'error' } rescue nil

      expect(configured).to be_open
    end
  end

  describe 'fallback' do
    let(:breaker_with_fallback) do
      described_class.new(
        name: 'test',
        failure_threshold: 1,
        fallback: -> { 'fallback_value' }
      )
    end

    it 'calls fallback when circuit is open' do
      breaker_with_fallback.call { raise 'error' } rescue nil
      result = breaker_with_fallback.call { 'should not execute' }
      expect(result).to eq('fallback_value')
    end
  end

  describe 'metrics and alerts' do
    it 'records transition and state metrics' do
      breaker = described_class.new(name: 'metrics', failure_threshold: 1)

      breaker.call { raise 'error' } rescue nil
      output = LePain::Metrics.to_prometheus

      expect(output).to include('circuit_breaker_transitions_total{name="metrics",from="closed",to="open"} 1')
      expect(output).to include('circuit_breaker_open_total{name="metrics"} 1')
      expect(output).to include('circuit_breaker_state{name="metrics",state="open"} 1.0')
    end

    it 'calls alert callback when circuit opens' do
      opened = []
      breaker = described_class.new(name: 'alerts', failure_threshold: 1, alert_callback: ->(b) { opened << b.name })

      breaker.call { raise 'error' } rescue nil

      expect(opened).to eq(['alerts'])
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      hash = breaker.to_h
      expect(hash[:name]).to eq('test')
      expect(hash[:state]).to eq(:closed)
      expect(hash[:failure_count]).to eq(0)
    end
  end
end

RSpec.describe 'Circuit breaker integrations' do
  before do
    LePain::CircuitBreaker.clear
  end

  it 'wraps MQ publish operations' do
    breaker = LePain::CircuitBreaker.new(name: 'kafka', failure_threshold: 1)
    LePain::CircuitBreaker.register('kafka', breaker)
    client = LePain::Transports::KafkaClient.new(brokers: ['localhost:9092'], group_id: 'spec')

    client.publish('orders', { id: 1 })

    expect(breaker.success_count).to eq(1)
  end

  it 'wraps Redis task store operations' do
    failing_redis = Class.new do
      def multi
        raise 'redis down'
      end
    end.new
    breaker = LePain::CircuitBreaker.new(name: 'redis_task_store', failure_threshold: 1)
    LePain::CircuitBreaker.register('redis_task_store', breaker)
    store = LePain::TaskStores::RedisStore.new(redis: failing_redis)

    store.create(LePain::Task.new(type: 'spec')) rescue nil

    expect(breaker).to be_open
  end
end
