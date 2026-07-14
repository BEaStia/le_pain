# frozen_string_literal: true

module LePain
  module Metrics
    class Histogram
      DEFAULT_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0].freeze

      attr_reader :name, :help, :labels, :buckets

      def initialize(name:, help:, labels: [], buckets: DEFAULT_BUCKETS)
        @name = name
        @help = help
        @labels = labels
        @buckets = buckets.sort
        @observations = {}
        @mutex = Mutex.new
      end

      def observe(value, labels = {})
        @mutex.synchronize do
          key = label_key(labels)
          @observations[key] ||= []
          @observations[key] << value.to_f
        end
      end

      def time(labels = {}, &block)
        start = Time.now
        result = yield
        elapsed = Time.now - start
        observe(elapsed, labels)
        result
      end

      def to_prometheus
        lines = []
        lines << "# HELP #{@name}_bucket #{@help}"
        lines << "# TYPE #{@name}_bucket histogram"

        @mutex.synchronize do
          @observations.each do |key, values|
            @buckets.each do |bucket|
              count = values.count { |v| v <= bucket }
              lines << "#{@name}_bucket{#{bucket_key(key, bucket)}} #{count}"
            end
            lines << "#{@name}_bucket{#{bucket_key(key, '+Inf')}} #{values.size}"
            lines << sample_line("#{@name}_sum", key, values.sum.round(6))
            lines << sample_line("#{@name}_count", key, values.size)
          end
        end

        lines.join("\n")
      end

      private

      def bucket_key(key, bucket)
        label = "le=\"#{bucket}\""
        key.empty? ? label : "#{key},#{label}"
      end

      def sample_line(name, key, value)
        key.empty? ? "#{name} #{value}" : "#{name}{#{key}} #{value}"
      end

      def label_key(labels)
        @labels.map { |l| "#{l}=\"#{labels[l.to_s] || ''}\"" }.join(',')
      end
    end
  end
end
