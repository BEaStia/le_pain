require 'spec_helper'

RSpec.describe LePain::Application do
  describe '.version' do
    it 'returns the correct version' do
      expect(LePain::VERSION).to eq('0.3.0')
    end
  end

  describe '.root' do
    it 'returns a path containing lib' do
      expect(described_class.root).to include('lib')
    end
  end

  describe '.config' do
    it 'loads the YAML configuration' do
      config = described_class.config
      expect(config).to be_a(Hash)
      expect(config).to have_key('environments')
    end
  end

  describe '.env' do
    it 'returns an Environment instance' do
      env = described_class.env
      expect(env).to be_a(LePain::Environment)
    end

    it 'responds to environment query methods' do
      env = described_class.env
      expect(env).to respond_to(:development?)
      expect(env).to respond_to(:production?)
      expect(env).to respond_to(:staging?)
    end

    it 'returns the current environment as string' do
      expect(described_class.env.to_s).to eq('development')
    end
  end

  describe '.logger' do
    it 'returns a Logger instance' do
      expect(described_class.logger).to be_a(Logger)
    end
  end

  describe '.configure_async_processing' do
    it 'configures retry policy and dead letter store from config' do
      allow(described_class).to receive(:config).and_return(
        'async' => {
          'retry' => {
            'max_attempts' => 5,
            'strategy' => 'linear',
            'backoff_base' => 0.25,
            'max_delay' => 2,
            'jitter' => false,
          },
          'dead_letter' => {
            'enabled' => true,
            'type' => 'memory',
            'ttl' => 10,
          },
        }
      )

      described_class.configure_async_processing

      expect(LePain::AsyncHandler.retry_policy.max_attempts).to eq(5)
      expect(LePain::AsyncHandler.retry_policy.strategy).to eq(:linear)
      expect(LePain::AsyncHandler.retry_policy.base_delay).to eq(0.25)
      expect(LePain::AsyncHandler.retry_policy.max_delay).to eq(2.0)
      expect(LePain::AsyncHandler.retry_policy.jitter).to be false
      expect(LePain::AsyncHandler.dead_letter_store).to be_a(LePain::TaskStores::MemoryStore)
    end
  end

  describe '.configure_health_check' do
    after do
      described_class.instance_variable_set(:@health_check, nil)
      described_class.instance_variable_set(:@task_store, nil)
    end

    it 'configures enhanced health probes from config' do
      allow(described_class).to receive(:config).and_return(
        'health_check' => {
          'enabled' => true,
          'startup_timeout' => 10,
          'readiness' => ['task_store'],
          'liveness' => ['deadlock_check'],
        },
        'task_store' => {
          'type' => 'memory',
          'options' => {},
        }
      )

      health_check = described_class.configure_health_check
      enhanced = health_check.enhanced

      expect(enhanced).to be_a(LePain::HealthCheckEnhanced::EnhancedHealthCheck)
      expect(enhanced.started?).to be true
      expect(enhanced.check_readiness[:status]).to eq(:healthy)
      expect(enhanced.check_liveness[:status]).to eq(:healthy)
    end
  end

  describe '#new' do
    it 'does not raise an error' do
      expect { described_class.new }.not_to raise_exception
    end
  end

  describe '#load' do
    it 'does not raise an error when loading post_initializers' do
      expect { described_class.new.load }.not_to raise_exception
    end
  end

  describe 'graceful shutdown' do
    it 'has a shutdown handler' do
      app = described_class.new
      expect(app.instance_variable_get(:@shutdown_handler)).to be_a(LePain::ShutdownHandler)
    end
  end
end
