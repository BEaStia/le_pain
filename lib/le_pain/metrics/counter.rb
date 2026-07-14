# frozen_string_literal: true

module LePain
  module Metrics
    class Counter
      attr_reader :name, :help, :labels

      def initialize(name:, help:, labels: [])
        @name = name
        @help = help
        @labels = labels
        @values = {}
        @mutex = Mutex.new
      end

      def increment(labels = {}, by: 1)
        @mutex.synchronize do
          key = label_key(labels)
          @values[key] ||= 0
          @values[key] += by
        end
      end

      def get(labels = {})
        @mutex.synchronize { @values[label_key(labels)] || 0 }
      end

      def to_prometheus
        lines = ["# HELP #{@name} #{@help}", "# TYPE #{@name} counter"]
        @mutex.synchronize do
          @values.each do |key, value|
            lines << sample_line(@name, key, value)
          end
        end
        lines.join("\n")
      end

      private

      def sample_line(name, key, value)
        key.empty? ? "#{name} #{value}" : "#{name}{#{key}} #{value}"
      end

      def label_key(labels)
        @labels.map { |l| "#{l}=\"#{labels[l.to_s] || ''}\"" }.join(',')
      end
    end
  end
end
