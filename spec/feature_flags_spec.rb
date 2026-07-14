require 'spec_helper'
require 'le_pain/feature_flags'

RSpec.describe LePain::FeatureFlags::Flag do
  describe '#initialize' do
    it 'sets name, enabled, strategy, and config' do
      flag = described_class.new(name: 'test', enabled: true, strategy: :boolean)
      expect(flag.name).to eq('test')
      expect(flag.enabled).to be true
      expect(flag.strategy).to eq(:boolean)
    end
  end

  describe '#evaluate' do
    context 'with boolean strategy' do
      it 'returns true when enabled' do
        flag = described_class.new(name: 'test', enabled: true, strategy: :boolean)
        expect(flag.evaluate).to be true
      end

      it 'returns false when disabled' do
        flag = described_class.new(name: 'test', enabled: false, strategy: :boolean)
        expect(flag.evaluate).to be false
      end
    end

    context 'with percentage strategy' do
      it 'evaluates based on percentage' do
        flag = described_class.new(
          name: 'test',
          enabled: true,
          strategy: :percentage,
          config: { percentage: 100 }
        )
        expect(flag.evaluate).to be true
      end

      it 'evaluates to false when percentage is 0' do
        flag = described_class.new(
          name: 'test',
          enabled: true,
          strategy: :percentage,
          config: { percentage: 0 }
        )
        expect(flag.evaluate).to be false
      end

      it 'uses seed for deterministic evaluation' do
        flag = described_class.new(
          name: 'test',
          enabled: true,
          strategy: :percentage,
          config: { percentage: 50, seed: :user_id }
        )
        # Same user_id should always get same result
        result1 = flag.evaluate(user_id: 'user-123')
        result2 = flag.evaluate(user_id: 'user-123')
        expect(result1).to eq(result2)
      end
    end

    context 'with user_targeted strategy' do
      it 'returns true for targeted users' do
        flag = described_class.new(
          name: 'test',
          enabled: true,
          strategy: :user_targeted,
          config: { users: ['user-1', 'user-2'] }
        )
        expect(flag.evaluate(user_id: 'user-1')).to be true
      end

      it 'returns false for non-targeted users' do
        flag = described_class.new(
          name: 'test',
          enabled: true,
          strategy: :user_targeted,
          config: { users: ['user-1', 'user-2'] }
        )
        expect(flag.evaluate(user_id: 'user-3')).to be false
      end

      it 'returns false when no user_id provided' do
        flag = described_class.new(
          name: 'test',
          enabled: true,
          strategy: :user_targeted,
          config: { users: ['user-1'] }
        )
        expect(flag.evaluate).to be false
      end
    end

    context 'with time_based strategy' do
      it 'returns true when within time window' do
        flag = described_class.new(
          name: 'test',
          enabled: true,
          strategy: :time_based,
          config: {
            enable_at: (Time.now - 3600).iso8601,
            disable_at: (Time.now + 3600).iso8601
          }
        )
        expect(flag.evaluate).to be true
      end

      it 'returns false before enable_at' do
        flag = described_class.new(
          name: 'test',
          enabled: true,
          strategy: :time_based,
          config: { enable_at: (Time.now + 3600).iso8601 }
        )
        expect(flag.evaluate).to be false
      end

      it 'returns false after disable_at' do
        flag = described_class.new(
          name: 'test',
          enabled: true,
          strategy: :time_based,
          config: { disable_at: (Time.now - 3600).iso8601 }
        )
        expect(flag.evaluate).to be false
      end
    end
  end
end

RSpec.describe LePain::FeatureFlags::Registry do
  let(:registry) { described_class.new }
  let(:flag) { LePain::FeatureFlags::Flag.new(name: 'test', enabled: true) }

  describe '#register' do
    it 'registers a flag' do
      registry.register(flag)
      expect(registry.get('test')).to eq(flag)
    end
  end

  describe '#get' do
    it 'returns flag by name' do
      registry.register(flag)
      expect(registry.get('test')).to eq(flag)
    end

    it 'returns nil for unknown flag' do
      expect(registry.get('unknown')).to be_nil
    end
  end

  describe '#enabled?' do
    it 'returns true for enabled flag' do
      registry.register(flag)
      expect(registry.enabled?('test')).to be true
    end

    it 'returns false for disabled flag' do
      disabled_flag = LePain::FeatureFlags::Flag.new(name: 'disabled', enabled: false)
      registry.register(disabled_flag)
      expect(registry.enabled?('disabled')).to be false
    end

    it 'returns false for unknown flag' do
      expect(registry.enabled?('unknown')).to be false
    end
  end

  describe '#all' do
    it 'returns all flags' do
      registry.register(flag)
      expect(registry.all).to include(flag)
    end
  end

  describe '#names' do
    it 'returns all flag names' do
      registry.register(flag)
      expect(registry.names).to include('test')
    end
  end

  describe '#clear' do
    it 'removes all flags' do
      registry.register(flag)
      registry.clear
      expect(registry.all).to be_empty
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      registry.register(flag)
      hash = registry.to_h
      expect(hash['test']).to be_a(Hash)
      expect(hash['test'][:enabled]).to be true
    end
  end
end

RSpec.describe LePain::FeatureFlags do
  before { described_class.clear }

  describe '.register' do
    it 'registers a flag' do
      flag = described_class.register('test', enabled: true)
      expect(flag).to be_a(LePain::FeatureFlags::Flag)
      expect(described_class.get('test')).to eq(flag)
    end
  end

  describe '.enabled?' do
    it 'checks if flag is enabled' do
      described_class.register('test', enabled: true)
      expect(described_class.enabled?('test')).to be true
    end

    it 'accepts context' do
      described_class.register(
        'test',
        enabled: true,
        strategy: :user_targeted,
        config: { users: ['user-1'] }
      )
      expect(described_class.enabled?('test', user_id: 'user-1')).to be true
      expect(described_class.enabled?('test', user_id: 'user-2')).to be false
    end
  end

  describe '.all' do
    it 'returns all flags' do
      described_class.register('test1', enabled: true)
      described_class.register('test2', enabled: false)
      expect(described_class.all.size).to eq(2)
    end
  end

  describe '.clear' do
    it 'removes all flags' do
      described_class.register('test', enabled: true)
      described_class.clear
      expect(described_class.all).to be_empty
    end
  end

  describe '.load_from_config' do
    it 'loads flags from config hash' do
      config = {
        'features' => {
          'feature1' => { 'enabled' => true, 'strategy' => 'boolean' },
          'feature2' => {
            'enabled' => true,
            'strategy' => 'percentage',
            'percentage' => 50
          }
        }
      }
      described_class.load_from_config(config)
      expect(described_class.enabled?('feature1')).to be true
      expect(described_class.get('feature2').strategy).to eq(:percentage)
    end
  end
end
