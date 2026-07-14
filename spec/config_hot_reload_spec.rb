require 'spec_helper'
require 'le_pain/config_hot_reload'
require 'tempfile'

RSpec.describe LePain::ConfigHotReload::Watcher do
  let(:config_file) do
    Tempfile.new(['config', '.yml']).tap do |f|
      f.write({
        'logger' => { 'level' => 'info' },
        'rate_limiting' => { 'limit' => 100 }
      }.to_yaml)
      f.rewind
    end
  end

  let(:watcher) do
    described_class.new(
      config_path: config_file.path,
      watch_interval: 1,
      reloadable_sections: %w[logger rate_limiting]
    )
  end

  after do
    watcher.stop if watcher.running?
    config_file.close
    config_file.unlink
  end

  describe '#initialize' do
    it 'sets config_path and watch_interval' do
      expect(watcher.config_path).to eq(config_file.path)
      expect(watcher.watch_interval).to eq(1)
    end

    it 'sets default reloadable_sections' do
      expect(watcher.reloadable_sections).to eq(%w[logger rate_limiting])
    end

    it 'initializes reload_count to 0' do
      expect(watcher.reload_count).to eq(0)
    end
  end

  describe '#start' do
    it 'starts the watcher' do
      watcher.start
      expect(watcher.running?).to be true
    end

    it 'does not start twice' do
      watcher.start
      watcher.start
      expect(watcher.running?).to be true
    end
  end

  describe '#stop' do
    it 'stops the watcher' do
      watcher.start
      watcher.stop
      expect(watcher.running?).to be false
    end
  end

  describe '#reload' do
    it 'reloads configuration' do
      result = watcher.reload
      expect(result[:reloaded]).to include('logger')
      expect(result[:reloaded]).to include('rate_limiting')
      expect(watcher.reload_count).to eq(1)
    end

    it 'returns empty arrays if config file does not exist' do
      watcher.instance_variable_set(:@config_path, '/nonexistent.yml')
      result = watcher.reload
      expect(result[:reloaded]).to eq([])
      expect(result[:failed]).to eq([])
    end

    it 'calls callbacks after reload' do
      callback_called = false
      watcher.on_reload { callback_called = true }
      watcher.reload
      expect(callback_called).to be true
    end
  end

  describe '#current_config' do
    it 'returns current configuration' do
      config = watcher.current_config
      expect(config).to be_a(Hash)
      expect(config['logger']).to be_a(Hash)
    end

    it 'returns empty hash if file does not exist' do
      watcher.instance_variable_set(:@config_path, '/nonexistent.yml')
      expect(watcher.current_config).to eq({})
    end
  end

  describe '#on_reload' do
    it 'registers callback' do
      callback = proc { }
      watcher.on_reload(&callback)
      expect(watcher.instance_variable_get(:@callbacks)).to include(callback)
    end
  end
end

RSpec.describe LePain::ConfigHotReload do
  let(:config_file) do
    Tempfile.new(['config', '.yml']).tap do |f|
      f.write({ 'logger' => { 'level' => 'info' } }.to_yaml)
      f.rewind
    end
  end

  after do
    described_class.stop
    config_file.close
    config_file.unlink
  end

  describe '.start' do
    it 'starts watcher with config' do
      watcher = described_class.start(config_path: config_file.path)
      expect(watcher).to be_a(LePain::ConfigHotReload::Watcher)
      expect(watcher.running?).to be true
    end
  end

  describe '.stop' do
    it 'stops watcher' do
      described_class.start(config_path: config_file.path)
      described_class.stop
      expect(described_class.watcher.running?).to be false
    end
  end

  describe '.reload' do
    it 'reloads configuration' do
      described_class.start(config_path: config_file.path)
      result = described_class.reload
      expect(result[:reloaded]).to include('logger')
    end
  end
end
