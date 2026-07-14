# frozen_string_literal: true

module LePain
  module Metrics
    class Summary
      DEFAULT_QUANTILES = [0.5, 0.9, 0.99].freeze

      attr_reader :name, :help, :labels, :quantiles

      def initialize(name:, help:, labels: [], quantiles: DEFAULT_QUANTILES)
        @name = name
        @help = help
        @labels = labels
        @quantiles = quantiles.sort
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

      def time(labels = {})
        start = Time.now
        result = yield
        observe(Time.now - start, labels)
        result
      end

      def to_prometheus
        lines = ["# HELP #{@name} #{@help}", "# TYPE #{@name} summary"]

        @mutex.synchronize do
          @observations.each do |key, values|
            sorted = values.sort
            @quantiles.each do |quantile|
              lines << "#{@name}{#{quantile_key(key, quantile)}} #{quantile_value(sorted, quantile)}"
            end
            lines << sample_line("#{@name}_sum", key, values.sum.round(6))
            lines << sample_line("#{@name}_count", key, values.size)
          end
        end

        lines.join("\n")
      end

      private

      def quantile_value(sorted, quantile)
        return 0 if sorted.empty?

        index = ((sorted.size - 1) * quantile).ceil
        sorted[index].round(6)
      end

      def quantile_key(key, quantile)
        label = "quantile=\"#{quantile}\""
        key.empty? ? label : "#{key},#{label}"
      end

      def sample_line(name, key, value)
        key.empty? ? "#{name} #{value}" : "#{name}{#{key}} #{value}"
      end

      def label_key(labels)
        @labels.map { |label| "#{label}=\"#{labels[label.to_s] || ''}\"" }.join(',')
      end
    end
  end
end
