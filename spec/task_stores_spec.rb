require 'spec_helper'

RSpec.describe LePain::TaskStores::MemoryStore do
  let(:store) { described_class.new(ttl: 1) }
  let(:task) { LePain::Task.new(type: 'report', payload: { user_id: '1' }) }

  describe '#create' do
    it 'stores the task' do
      store.create(task)
      expect(store.find(task.id)).to eq(task)
    end
  end

  describe '#find' do
    it 'returns nil for missing tasks' do
      expect(store.find('missing')).to be_nil
    end

    it 'expires finished tasks after TTL' do
      task.start!
      task.complete!({})
      store.create(task)
      sleep 1.1
      expect(store.find(task.id)).to be_nil
    end
  end

  describe '#update' do
    it 'yields the task and saves changes' do
      store.create(task)
      store.update(task.id) { |t| t.complete!({ result: 'ok' }) }
      expect(store.find(task.id).result).to eq({ result: 'ok' })
    end

    it 'returns nil for missing tasks' do
      expect(store.update('missing') { |t| t.complete!({}) }).to be_nil
    end
  end

  describe '#list' do
    it 'returns tasks sorted by created_at descending' do
      t1 = LePain::Task.new(type: 'r1')
      sleep 0.01
      t2 = LePain::Task.new(type: 'r2')
      store.create(t1)
      store.create(t2)
      expect(store.list.map(&:id)).to eq([t2.id, t1.id])
    end

    it 'filters by state' do
      t1 = LePain::Task.new(type: 'r1')
      t2 = LePain::Task.new(type: 'r2')
      t2.complete!({})
      store.create(t1)
      store.create(t2)
      expect(store.list(state: 'completed').map(&:id)).to eq([t2.id])
    end

    it 'respects limit' do
      5.times { |i| store.create(LePain::Task.new(type: "r#{i}")) }
      expect(store.list(limit: 2).size).to eq(2)
    end
  end

  describe '#size' do
    it 'returns the number of tasks' do
      store.create(LePain::Task.new(type: 'r1'))
      store.create(LePain::Task.new(type: 'r2'))
      expect(store.size).to eq(2)
    end
  end

  describe '#clear' do
    it 'removes all tasks' do
      store.create(LePain::Task.new(type: 'r1'))
      store.clear
      expect(store.size).to eq(0)
    end
  end
end
