require 'spec_helper'

RSpec.describe LePain::Context do
  describe '.new' do
    it 'generates request_id if not provided' do
      ctx = described_class.new
      expect(ctx.request_id).to be_a(String)
      expect(ctx.request_id).not_to be_empty
    end

    it 'sets trace_id to request_id if not provided' do
      ctx = described_class.new(request_id: 'req-1')
      expect(ctx.trace_id).to eq('req-1')
    end

    it 'sets correlation_id to trace_id if not provided' do
      ctx = described_class.new(trace_id: 'trace-1')
      expect(ctx.correlation_id).to eq('trace-1')
    end

    it 'accepts all parameters' do
      ctx = described_class.new(
        request_id: 'r1', trace_id: 't1', correlation_id: 'c1',
        idempotency_key: 'i1', transport: :mq, auth: 'Bearer xyz',
        metadata: { foo: 'bar' },
      )
      expect(ctx.request_id).to eq('r1')
      expect(ctx.trace_id).to eq('t1')
      expect(ctx.correlation_id).to eq('c1')
      expect(ctx.idempotency_key).to eq('i1')
      expect(ctx.transport).to eq(:mq)
      expect(ctx.auth).to eq('Bearer xyz')
    end
  end

  describe '.current' do
    it 'returns a new context when none is set' do
      described_class.clear
      ctx = described_class.current
      expect(ctx).to be_a(described_class)
    end

    it 'returns the same context within a fiber' do
      described_class.clear
      ctx1 = described_class.current
      ctx2 = described_class.current
      expect(ctx1).to eq(ctx2)
    end
  end

  describe '.with' do
    it 'sets context for the block duration' do
      ctx = described_class.new(request_id: 'test-1')
      described_class.with(ctx) do
        expect(described_class.current.request_id).to eq('test-1')
      end
    end

    it 'restores previous context after block' do
      outer = described_class.new(request_id: 'outer')
      inner = described_class.new(request_id: 'inner')

      described_class.with(outer) do
        described_class.with(inner) do
          expect(described_class.current.request_id).to eq('inner')
        end
        expect(described_class.current.request_id).to eq('outer')
      end
    end
  end

  describe '#with' do
    it 'returns a new context with merged metadata' do
      ctx = described_class.new(request_id: 'r1', metadata: { a: 1 })
      new_ctx = ctx.with({ b: 2 })
      expect(new_ctx.request_id).to eq('r1')
      expect(new_ctx.metadata).to eq({ a: 1, b: 2 })
    end

    it 'supports keyword overrides' do
      ctx = described_class.new(request_id: 'r1', trace_id: 't1')
      new_ctx = ctx.with({}, trace_id: 't2')
      expect(new_ctx.trace_id).to eq('t2')
      expect(new_ctx.request_id).to eq('r1')
    end
  end

  describe '#expired?' do
    it 'returns false when no deadline' do
      expect(described_class.new.expired?).to be false
    end

    it 'returns true when deadline is in the past' do
      ctx = described_class.new(deadline: Time.now - 10)
      expect(ctx.expired?).to be true
    end

    it 'returns false when deadline is in the future' do
      ctx = described_class.new(deadline: Time.now + 10)
      expect(ctx.expired?).to be false
    end
  end

  describe '#to_h' do
    it 'returns a hash with all fields' do
      ctx = described_class.new(request_id: 'r1', trace_id: 't1', transport: :http)
      h = ctx.to_h
      expect(h[:request_id]).to eq('r1')
      expect(h[:trace_id]).to eq('t1')
      expect(h[:transport]).to eq(:http)
    end
  end
end
