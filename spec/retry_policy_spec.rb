require 'spec_helper'
require 'le_pain/retry_policy'

RSpec.describe LePain::RetryPolicy do
  describe '#initialize' do
    it 'sets defaults' do
      policy = described_class.new
      expect(policy.max_attempts).to eq(3)
      expect(policy.strategy).to eq(:exponential)
      expect(policy.base_delay).to eq(1.0)
      expect(policy.max_delay).to eq(60.0)
      expect(policy.jitter).to be true
    end

    it 'raises on invalid strategy' do
      expect { described_class.new(strategy: :invalid) }.to raise_error(ArgumentError)
    end
  end

  describe '#execute' do
    it 'returns result on first success' do
      policy = described_class.new(max_attempts: 3)
      result = policy.execute { 'success' }
      expect(result).to eq('success')
    end

    it 'retries on failure and returns result' do
      policy = described_class.new(max_attempts: 3, base_delay: 0.01)
      attempts = 0
      result = policy.execute do
        attempts += 1
        raise 'error' if attempts < 3
        'success'
      end
      expect(result).to eq('success')
      expect(attempts).to eq(3)
    end

    it 'raises after max_attempts' do
      policy = described_class.new(max_attempts: 2, base_delay: 0.01)
      expect { policy.execute { raise 'error' } }.to raise_error('error')
    end

    it 'only retries on specified exceptions' do
      policy = described_class.new(max_attempts: 3, base_delay: 0.01, retry_on: [RuntimeError])
      expect { policy.execute { raise ArgumentError, 'bad arg' } }.to raise_error(ArgumentError)
    end
  end

  describe '#calculate_delay' do
    context 'fixed strategy' do
      let(:policy) { described_class.new(strategy: :fixed, base_delay: 2.0, jitter: false) }

      it 'returns constant delay' do
        expect(policy.calculate_delay(1)).to eq(2.0)
        expect(policy.calculate_delay(2)).to eq(2.0)
        expect(policy.calculate_delay(3)).to eq(2.0)
      end
    end

    context 'linear strategy' do
      let(:policy) { described_class.new(strategy: :linear, base_delay: 1.0, jitter: false) }

      it 'returns linearly increasing delay' do
        expect(policy.calculate_delay(1)).to eq(1.0)
        expect(policy.calculate_delay(2)).to eq(2.0)
        expect(policy.calculate_delay(3)).to eq(3.0)
      end
    end

    context 'exponential strategy' do
      let(:policy) { described_class.new(strategy: :exponential, base_delay: 1.0, jitter: false) }

      it 'returns exponentially increasing delay' do
        expect(policy.calculate_delay(1)).to eq(1.0)
        expect(policy.calculate_delay(2)).to eq(2.0)
        expect(policy.calculate_delay(3)).to eq(4.0)
        expect(policy.calculate_delay(4)).to eq(8.0)
      end
    end

    context 'max_delay' do
      let(:policy) { described_class.new(strategy: :exponential, base_delay: 1.0, max_delay: 5.0, jitter: false) }

      it 'caps delay at max_delay' do
        expect(policy.calculate_delay(10)).to eq(5.0)
      end
    end

    context 'jitter' do
      let(:policy) { described_class.new(strategy: :fixed, base_delay: 2.0, jitter: true) }

      it 'applies jitter' do
        delays = 10.times.map { policy.calculate_delay(1) }
        expect(delays.uniq.size).to be > 1
        expect(delays.all? { |d| d >= 1.0 && d <= 2.0 }).to be true
      end
    end
  end
end
