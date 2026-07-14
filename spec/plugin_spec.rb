require 'spec_helper'
require 'le_pain/plugin'

RSpec.describe LePain::Plugin::Base do
  let(:plugin) { described_class.new(name: 'test-plugin', version: '1.0.0', config: { key: 'value' }) }

  describe '#initialize' do
    it 'sets name, version, and config' do
      expect(plugin.name).to eq('test-plugin')
      expect(plugin.version).to eq('1.0.0')
      expect(plugin.config).to eq({ key: 'value' })
    end

    it 'starts as not initialized' do
      expect(plugin.initialized?).to be false
    end
  end

  describe '#initialize_plugin' do
    it 'marks as initialized' do
      plugin.initialize_plugin(nil)
      expect(plugin.initialized?).to be true
    end

    it 'calls on_initialize only once' do
      call_count = 0
      allow(plugin).to receive(:on_initialize) { call_count += 1 }

      plugin.initialize_plugin(nil)
      plugin.initialize_plugin(nil)

      expect(call_count).to eq(1)
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      hash = plugin.to_h
      expect(hash[:name]).to eq('test-plugin')
      expect(hash[:version]).to eq('1.0.0')
      expect(hash[:initialized]).to be false
      expect(hash[:config]).to eq({ key: 'value' })
    end
  end
end

RSpec.describe LePain::Plugin::Registry do
  let(:registry) { described_class.new }
  let(:plugin1) { LePain::Plugin::Base.new(name: 'plugin1') }
  let(:plugin2) { LePain::Plugin::Base.new(name: 'plugin2') }

  describe '#register' do
    it 'registers a plugin' do
      registry.register(plugin1)
      expect(registry.get('plugin1')).to eq(plugin1)
    end

    it 'raises error if plugin already registered' do
      registry.register(plugin1)
      expect { registry.register(plugin1) }.to raise_error(ArgumentError)
    end
  end

  describe '#get' do
    it 'returns plugin by name' do
      registry.register(plugin1)
      expect(registry.get('plugin1')).to eq(plugin1)
    end

    it 'returns nil for unknown plugin' do
      expect(registry.get('unknown')).to be_nil
    end
  end

  describe '#all' do
    it 'returns all plugins in load order' do
      registry.register(plugin1)
      registry.register(plugin2)
      expect(registry.all).to eq([plugin1, plugin2])
    end
  end

  describe '#names' do
    it 'returns plugin names in load order' do
      registry.register(plugin1)
      registry.register(plugin2)
      expect(registry.names).to eq(['plugin1', 'plugin2'])
    end
  end

  describe '#size' do
    it 'returns number of plugins' do
      registry.register(plugin1)
      registry.register(plugin2)
      expect(registry.size).to eq(2)
    end
  end

  describe '#clear' do
    it 'removes all plugins' do
      registry.register(plugin1)
      registry.clear
      expect(registry.size).to eq(0)
    end
  end

  describe '#initialize_all' do
    it 'initializes all plugins' do
      registry.register(plugin1)
      registry.register(plugin2)
      registry.initialize_all(nil)
      expect(plugin1.initialized?).to be true
      expect(plugin2.initialized?).to be true
    end
  end

  describe '#start_all' do
    it 'starts all plugins' do
      registry.register(plugin1)
      registry.register(plugin2)
      expect(plugin1).to receive(:on_start).with(nil)
      expect(plugin2).to receive(:on_start).with(nil)
      registry.start_all(nil)
    end
  end

  describe '#stop_all' do
    it 'stops all plugins in reverse order' do
      registry.register(plugin1)
      registry.register(plugin2)
      expect(plugin2).to receive(:on_stop).with(nil).ordered
      expect(plugin1).to receive(:on_stop).with(nil).ordered
      registry.stop_all(nil)
    end
  end

  describe '#to_h' do
    it 'returns array of plugin hashes' do
      registry.register(plugin1)
      registry.register(plugin2)
      result = registry.to_h
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first[:name]).to eq('plugin1')
    end
  end
end

RSpec.describe LePain::Plugin do
  before { described_class.clear }

  describe '.register' do
    it 'registers plugin to global registry' do
      plugin = LePain::Plugin::Base.new(name: 'global-plugin')
      described_class.register(plugin)
      expect(described_class.get('global-plugin')).to eq(plugin)
    end
  end

  describe '.all' do
    it 'returns all registered plugins' do
      plugin1 = LePain::Plugin::Base.new(name: 'p1')
      plugin2 = LePain::Plugin::Base.new(name: 'p2')
      described_class.register(plugin1)
      described_class.register(plugin2)
      expect(described_class.all.size).to eq(2)
    end
  end

  describe '.initialize_all' do
    it 'initializes all plugins' do
      plugin = LePain::Plugin::Base.new(name: 'test')
      described_class.register(plugin)
      described_class.initialize_all(nil)
      expect(plugin.initialized?).to be true
    end
  end

  describe '.clear' do
    it 'clears global registry' do
      plugin = LePain::Plugin::Base.new(name: 'test')
      described_class.register(plugin)
      described_class.clear
      expect(described_class.all.size).to eq(0)
    end
  end
end
