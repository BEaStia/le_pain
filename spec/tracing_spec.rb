require 'spec_helper'
require 'le_pain/tracing'

RSpec.describe LePain::Tracing::Span do
  let(:span) { described_class.new(name: 'test-span') }

  describe '#initialize' do
    it 'generates trace_id and span_id' do
      expect(span.trace_id).to be_a(String)
      expect(span.trace_id.length).to eq(32)
      expect(span.span_id).to be_a(String)
      expect(span.span_id.length).to eq(16)
    end

    it 'sets name and kind' do
      expect(span.name).to eq('test-span')
      expect(span.kind).to eq(:internal)
    end

    it 'accepts parent_span_id' do
      parent_span = described_class.new(name: 'parent')
      child_span = described_class.new(name: 'child', parent_span_id: parent_span.span_id)
      expect(child_span.parent_span_id).to eq(parent_span.span_id)
    end

    it 'accepts trace_id for propagation' do
      trace_id = 'abc123' * 4
      span = described_class.new(name: 'test', trace_id: trace_id)
      expect(span.trace_id).to eq(trace_id)
    end
  end

  describe '#set_attribute' do
    it 'sets attributes' do
      span.set_attribute('http.method', 'GET')
      expect(span.attributes['http.method']).to eq('GET')
    end
  end

  describe '#add_event' do
    it 'adds events' do
      span.add_event('test-event', attributes: { key: 'value' })
      expect(span.events.size).to eq(1)
      expect(span.events.first[:name]).to eq('test-event')
    end
  end

  describe '#set_status' do
    it 'sets status' do
      span.set_status(:ok)
      expect(span.status).to eq(:ok)
    end
  end

  describe '#finish' do
    it 'sets end_time' do
      span.finish
      expect(span.end_time).to be_a(Time)
    end
  end

  describe '#duration' do
    it 'returns nil if not finished' do
      expect(span.duration).to be_nil
    end

    it 'returns duration after finish' do
      span.finish
      expect(span.duration).to be >= 0
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      span.finish
      hash = span.to_h
      expect(hash[:trace_id]).to eq(span.trace_id)
      expect(hash[:span_id]).to eq(span.span_id)
      expect(hash[:name]).to eq('test-span')
      expect(hash[:duration]).to be_a(Float)
    end
  end
end

RSpec.describe LePain::Tracing::ConsoleExporter do
  let(:output) { StringIO.new }
  let(:exporter) { described_class.new(output: output) }
  let(:span) { LePain::Tracing::Span.new(name: 'test') }

  before { span.finish }

  describe '#export' do
    it 'outputs JSON to console' do
      exporter.export([span])
      expect(output.string).to include('test')
      expect(output.string).to include('trace_id')
    end
  end
end

RSpec.describe LePain::Tracing::Tracer do
  let(:exporter) { instance_double(LePain::Tracing::Exporter, export: nil, shutdown: nil) }
  let(:tracer) { described_class.new(exporter: exporter) }

  describe '#start_span' do
    it 'creates a span' do
      span = tracer.start_span('test')
      expect(span).to be_a(LePain::Tracing::Span)
      expect(span.name).to eq('test')
    end

    it 'creates child span with parent' do
      parent = tracer.start_span('parent')
      child = tracer.start_span('child', parent: parent)
      expect(child.trace_id).to eq(parent.trace_id)
      expect(child.parent_span_id).to eq(parent.span_id)
    end
  end

  describe '#in_span' do
    it 'yields span and finishes it' do
      result = tracer.in_span('test') do |span|
        expect(span).to be_a(LePain::Tracing::Span)
        'result'
      end
      expect(result).to eq('result')
      expect(exporter).to have_received(:export)
    end

    it 'sets error status on exception' do
      expect {
        tracer.in_span('test') { raise 'error' }
      }.to raise_error('error')
      expect(exporter).to have_received(:export)
    end
  end

  describe '#shutdown' do
    it 'calls exporter shutdown' do
      tracer.shutdown
      expect(exporter).to have_received(:shutdown)
    end
  end
end

RSpec.describe LePain::Tracing do
  describe '.configure' do
    it 'sets custom exporter' do
      exporter = LePain::Tracing::ConsoleExporter.new
      described_class.configure(exporter: exporter)
      expect(described_class.tracer).to be_a(LePain::Tracing::Tracer)
    end
  end

  describe '.in_span' do
    it 'delegates to tracer' do
      result = described_class.in_span('test') { 'value' }
      expect(result).to eq('value')
    end
  end
end
