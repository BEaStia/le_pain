require 'spec_helper'
require 'le_pain/circuit_breaker'

RSpec.describe LePain::CircuitBreaker do
  let(:breaker) { described_class.new(name: 'test', failure_threshold: 3, success_threshold: 2, timeout: 1) }

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

  describe '#to_h' do
    it 'returns hash representation' do
      hash = breaker.to_h
      expect(hash[:name]).to eq('test')
      expect(hash[:state]).to eq(:closed)
      expect(hash[:failure_count]).to eq(0)
    end
  end
end
