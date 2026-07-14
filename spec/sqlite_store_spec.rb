require 'spec_helper'
require 'le_pain/task_stores/sqlite_store'
require 'tmpdir'

RSpec.describe LePain::TaskStores::SqliteStore do
  let(:store) { described_class.new(database: ':memory:', ttl: 86400) }
  let(:task) { LePain::Task.new(type: 'test', payload: { key: 'value' }) }

  after do
    store.close
  end

  describe '#create' do
    it 'creates a task' do
      expect { store.create(task) }.not_to raise_error
    end

    it 'persists the task' do
      store.create(task)
      found = store.find(task.id)
      expect(found).not_to be_nil
      expect(found.id).to eq(task.id)
    end
  end

  describe '#find' do
    context 'when task exists' do
      before { store.create(task) }

      it 'returns the task' do
        found = store.find(task.id)
        expect(found).to be_a(LePain::Task)
        expect(found.id).to eq(task.id)
        expect(found.type).to eq('test')
      end

      it 'deserializes payload correctly' do
        found = store.find(task.id)
        expect(found.payload).to eq({ 'key' => 'value' })
      end
    end

    context 'when task does not exist' do
      it 'returns nil' do
        expect(store.find('nonexistent')).to be_nil
      end
    end

    context 'when task is expired' do
      let(:expired_store) { described_class.new(database: ':memory:', ttl: 1) }
      let(:completed_task) do
        task = LePain::Task.new(type: 'test')
        task.complete!('done')
        task
      end

      after { expired_store.close }

      it 'returns nil for expired completed tasks' do
        expired_store.create(completed_task)
        sleep 1.1
        expect(expired_store.find(completed_task.id)).to be_nil
      end
    end
  end

  describe '#update' do
    before { store.create(task) }

    it 'updates task state' do
      store.update(task.id) do |t|
        t.complete!('result')
      end

      updated = store.find(task.id)
      expect(updated.state).to eq('completed')
      expect(updated.result).to eq('result')
    end

    it 'updates updated_at timestamp' do
      original_updated_at = store.find(task.id).updated_at
      sleep 1.1  # SQLite stores timestamps with second precision

      store.update(task.id) do |t|
        t.complete!('done')
      end

      updated = store.find(task.id)
      expect(updated.updated_at).to be > original_updated_at
    end

    context 'when task does not exist' do
      it 'returns nil' do
        result = store.update('nonexistent') { |t| t.complete!('done') }
        expect(result).to be_nil
      end
    end
  end

  describe '#list' do
    before do
      5.times do |i|
        store.create(LePain::Task.new(type: "type_#{i % 2}", payload: { index: i }))
      end
    end

    it 'returns all tasks by default' do
      tasks = store.list
      expect(tasks.size).to eq(5)
    end

    it 'limits results' do
      tasks = store.list(limit: 3)
      expect(tasks.size).to eq(3)
    end

    it 'filters by state' do
      first_task = store.list.first
      store.update(first_task.id) { |t| t.complete!('done') }
      completed = store.list(state: 'completed')
      expect(completed.size).to eq(1)
      expect(completed.first.state).to eq('completed')
    end

    it 'filters by type' do
      tasks = store.list(type: 'type_0')
      expect(tasks.size).to eq(3)
      expect(tasks.all? { |t| t.type == 'type_0' }).to be true
    end

    it 'orders by created_at DESC' do
      tasks = store.list
      timestamps = tasks.map(&:created_at)
      expect(timestamps).to eq(timestamps.sort.reverse)
    end
  end

  describe '#delete' do
    before { store.create(task) }

    it 'deletes the task' do
      store.delete(task.id)
      expect(store.find(task.id)).to be_nil
    end

    it 'does not raise error for nonexistent task' do
      expect { store.delete('nonexistent') }.not_to raise_error
    end
  end

  describe '#cleanup' do
    let(:expired_store) { described_class.new(database: ':memory:', ttl: 1) }

    after { expired_store.close }

    it 'removes expired completed tasks' do
      completed_task = LePain::Task.new(type: 'test')
      completed_task.complete!('done')
      expired_store.create(completed_task)

      pending_task = LePain::Task.new(type: 'test')
      expired_store.create(pending_task)

      sleep 1.1
      expired_store.cleanup

      expect(expired_store.find(completed_task.id)).to be_nil
      expect(expired_store.find(pending_task.id)).not_to be_nil
    end

    it 'keeps non-expired tasks' do
      task = LePain::Task.new(type: 'test')
      task.complete!('done')
      expired_store.create(task)

      expired_store.cleanup
      expect(expired_store.find(task.id)).not_to be_nil
    end
  end

  describe '#size' do
    it 'returns 0 for empty store' do
      expect(store.size).to eq(0)
    end

    it 'returns correct count' do
      3.times { store.create(LePain::Task.new(type: 'test')) }
      expect(store.size).to eq(3)
    end
  end

  describe '#clear' do
    before do
      3.times { store.create(LePain::Task.new(type: 'test')) }
    end

    it 'removes all tasks' do
      store.clear
      expect(store.size).to eq(0)
    end
  end

  describe 'file-based database' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:db_path) { File.join(tmpdir, 'tasks.db') }
    let(:file_store) { described_class.new(database: db_path) }

    after do
      file_store.close
      FileUtils.rm_rf(tmpdir)
    end

    it 'persists data to file' do
      file_store.create(task)
      file_store.close

      new_store = described_class.new(database: db_path)
      expect(new_store.find(task.id)).not_to be_nil
      new_store.close
    end
  end

  describe 'complex payloads' do
    it 'handles nested hashes' do
      complex_task = LePain::Task.new(
        type: 'test',
        payload: {
          user: { id: 1, name: 'John' },
          items: [1, 2, 3],
          metadata: { key: 'value' }
        }
      )

      store.create(complex_task)
      found = store.find(complex_task.id)

      expect(found.payload['user']['id']).to eq(1)
      expect(found.payload['items']).to eq([1, 2, 3])
    end

    it 'handles nil values' do
      nil_task = LePain::Task.new(type: 'test', payload: { key: nil })
      store.create(nil_task)
      found = store.find(nil_task.id)
      expect(found.payload['key']).to be_nil
    end
  end
end
