# frozen_string_literal: true

require 'securerandom'
require 'json'

module LePain
  module Tracing
    class Span
      attr_reader :trace_id, :span_id, :parent_span_id, :name, :start_time, :end_time,
                  :attributes, :events, :status, :kind

      def initialize(name:, trace_id: nil, parent_span_id: nil, kind: :internal)
        @trace_id = trace_id || generate_trace_id
        @span_id = generate_span_id
        @parent_span_id = parent_span_id
        @name = name
        @kind = kind
        @start_time = Time.now
        @end_time = nil
        @attributes = {}
        @events = []
        @status = :unset
      end

      def set_attribute(key, value)
        @attributes[key.to_s] = value
      end

      def add_event(name, attributes: {})
        @events << {
          name: name,
          timestamp: Time.now.iso8601(6),
          attributes: attributes,
        }
      end

      def set_status(status, description: nil)
        @status = status
        @status_description = description
      end

      def finish
        @end_time = Time.now
      end

      def duration
        return nil unless @end_time

        @end_time - @start_time
      end

      def to_h
        {
          trace_id: @trace_id,
          span_id: @span_id,
          parent_span_id: @parent_span_id,
          name: @name,
          kind: @kind,
          start_time: @start_time.iso8601(6),
          end_time: @end_time&.iso8601(6),
          duration: duration,
          attributes: @attributes,
          events: @events,
          status: @status,
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      private

      def generate_trace_id
        SecureRandom.hex(16)
      end

      def generate_span_id
        SecureRandom.hex(8)
      end
    end

    class Exporter
      def export(spans)
        raise NotImplementedError
      end

      def shutdown
        # Override in subclasses
      end
    end

    class ConsoleExporter < Exporter
      def initialize(output: STDOUT)
        @output = output
      end

      def export(spans)
        spans.each do |span|
          @output.puts JSON.pretty_generate(span.to_h)
        end
      end
    end

    class OtlpExporter < Exporter
      def initialize(endpoint: 'http://localhost:4318/v1/traces', headers: {})
        @endpoint = endpoint
        @headers = headers
        @buffer = []
        @buffer_size = 100
      end

      def export(spans)
        @buffer.concat(spans.map(&:to_h))
        flush if @buffer.size >= @buffer_size
      end

      def flush
        return if @buffer.empty?

        payload = {
          resourceSpans: [
            {
              resource: {
                attributes: [
                  { key: 'service.name', value: { stringValue: 'le_pain' } },
                ],
              },
              scopeSpans: [
                {
                  scope: { name: 'le_pain' },
                  spans: @buffer.map { |s| convert_to_otlp(s) },
                },
              ],
            },
          ],
        }

        send_to_collector(payload)
        @buffer.clear
      end

      def shutdown
        flush
      end

      private

      def convert_to_otlp(span)
        {
          traceId: span[:trace_id],
          spanId: span[:span_id],
          parentSpanId: span[:parent_span_id] || '',
          name: span[:name],
          kind: convert_kind(span[:kind]),
          startTimeUnixNano: (span[:start_time].to_f * 1_000_000_000).to_i,
          endTimeUnixNano: span[:end_time] ? (span[:end_time].to_f * 1_000_000_000).to_i : 0,
          attributes: span[:attributes].map do |k, v|
            { key: k, value: convert_value(v) }
          end,
          events: span[:events].map do |e|
            {
              timeUnixNano: (Time.parse(e[:timestamp]).to_f * 1_000_000_000).to_i,
              name: e[:name],
              attributes: e[:attributes].map { |k, v| { key: k, value: convert_value(v) } },
            }
          end,
          status: { code: convert_status(span[:status]) },
        }
      end

      def convert_kind(kind)
        case kind
        when :server then 2
        when :client then 3
        when :producer then 4
        when :consumer then 5
        else 1 # INTERNAL
        end
      end

      def convert_status(status)
        case status
        when :ok then 2
        when :error then 3
        else 0 # UNSET
        end
      end

      def convert_value(value)
        case value
        when String then { stringValue: value }
        when Integer then { intValue: value }
        when Float then { doubleValue: value }
        when TrueClass, FalseClass then { boolValue: value }
        else { stringValue: value.to_s }
        end
      end

      def send_to_collector(payload)
        require 'net/http'
        require 'uri'

        uri = URI(@endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'

        request = Net::HTTP::Post.new(uri.path)
        request['Content-Type'] = 'application/json'
        @headers.each { |k, v| request[k] = v }
        request.body = JSON.generate(payload)

        http.request(request)
      rescue StandardError => e
        LePain::Application.logger.error("Failed to export traces: #{e.message}")
      end
    end

    class Tracer
      def initialize(exporter: nil)
        @exporter = exporter || ConsoleExporter.new
        @spans = []
        @mutex = Mutex.new
      end

      def start_span(name, parent: nil, kind: :internal)
        trace_id = parent ? parent.trace_id : nil
        parent_span_id = parent ? parent.span_id : nil

        span = Span.new(
          name: name,
          trace_id: trace_id,
          parent_span_id: parent_span_id,
          kind: kind,
        )

        @mutex.synchronize { @spans << span }
        span
      end

      def in_span(name, parent: nil, kind: :internal)
        span = start_span(name, parent: parent, kind: kind)
        yield span
      rescue StandardError => e
        span.set_status(:error, description: e.message)
        span.add_event('exception', attributes: { 'exception.message' => e.message })
        raise
      ensure
        span.finish
        export_span(span)
      end

      def export_span(span)
        @exporter.export([span])
      end

      def shutdown
        @exporter.shutdown
      end
    end

    class << self
      def tracer
        @tracer ||= Tracer.new
      end

      def configure(exporter:)
        @tracer = Tracer.new(exporter: exporter)
      end

      def in_span(name, &block)
        tracer.in_span(name, &block)
      end

      def shutdown
        tracer.shutdown
      end
    end
  end
end
