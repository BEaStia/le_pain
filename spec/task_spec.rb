require 'spec_helper'

RSpec.describe LePain::Task do
  describe '.new' do
    it 'creates a pending task' do
      task = described_class.new(type: 'report', payload: { user_id: '1' })
      expect(task.state).to eq('pending')
      expect(task.type).to eq('report')
    end

    it 'generates an ID if not provided' do
      task = described_class.new(type: 'report')
      expect(task.id).to be_a(String)
    end
  end

  describe '#start!' do
    it 'transitions to running' do
      task = described_class.new(type: 'report')
      task.start!
      expect(task.running?).to be true
      expect(task.started_at).not_to be_nil
    end
  end

  describe '#complete!' do
    it 'transitions to completed with result' do
      task = described_class.new(type: 'report')
      task.start!
      task.complete!({ url: '/report' })
      expect(task.completed?).to be true
      expect(task.result).to eq({ url: '/report' })
      expect(task.duration).not_to be_nil
    end
  end

  describe '#fail!' do
    it 'transitions to failed with error' do
      task = described_class.new(type: 'report')
      task.start!
      task.fail!(StandardError.new('timeout'))
      expect(task.failed?).to be true
      expect(task.error[:message]).to eq('timeout')
    end
  end

  describe '#increment_attempt!' do
    it 'tracks execution attempts' do
      task = described_class.new(type: 'report')

      task.increment_attempt!
      task.increment_attempt!

      expect(task.attempts).to eq(2)
    end
  end

  describe '#reset_for_retry!' do
    it 'resets terminal state and attempts' do
      task = described_class.new(type: 'report')
      task.start!
      task.increment_attempt!
      task.fail!(StandardError.new('timeout'))

      task.reset_for_retry!

      expect(task.pending?).to be true
      expect(task.attempts).to eq(0)
      expect(task.error).to be_nil
      expect(task.completed_at).to be_nil
    end
  end

  describe '#cancel!' do
    it 'transitions to cancelled' do
      task = described_class.new(type: 'report')
      task.cancel!
      expect(task.cancelled?).to be true
    end
  end

  describe '#finished?' do
    it 'returns true for completed, failed, cancelled' do
      t1 = described_class.new(type: 'r'); t1.complete!({})
      t2 = described_class.new(type: 'r'); t2.fail!(StandardError.new('x'))
      t3 = described_class.new(type: 'r'); t3.cancel!
      t4 = described_class.new(type: 'r')
      expect(t1.finished?).to be true
      expect(t2.finished?).to be true
      expect(t3.finished?).to be true
      expect(t4.finished?).to be false
    end
  end

  describe '.from_hash' do
    it 'reconstructs a task from hash data' do
      task = described_class.new(type: 'report', payload: { user_id: '1' })
      task.start!
      task.complete!({ url: '/r' })

      data = task.to_h
      restored = described_class.from_hash(data)

      expect(restored.id).to eq(task.id)
      expect(restored.type).to eq(task.type)
      expect(restored.state).to eq(task.state)
      expect(restored.result).to eq(task.result)
      expect(restored.attempts).to eq(task.attempts)
    end
  end

  describe '#to_h' do
    it 'returns string keys' do
      task = described_class.new(type: 'report')
      h = task.to_h
      expect(h['id']).to eq(task.id)
      expect(h['type']).to eq('report')
      expect(h['state']).to eq('pending')
    end
  end
end
