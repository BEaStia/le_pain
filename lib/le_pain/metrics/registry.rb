# frozen_string_literal: true

require_relative 'counter'
require_relative 'gauge'
require_relative 'histogram'
require_relative 'summary'

module LePain
  module Metrics
    class Registry
      def initialize
        @metrics = {}
        @mutex = Mutex.new
      end

      def counter(name, help, labels: [])
        fetch_or_create(name) { Counter.new(name: name, help: help, labels: labels) }
      end

      def gauge(name, help, labels: [])
        fetch_or_create(name) { Gauge.new(name: name, help: help, labels: labels) }
      end

      def histogram(name, help, labels: [], buckets: Histogram::DEFAULT_BUCKETS)
        fetch_or_create(name) { Histogram.new(name: name, help: help, labels: labels, buckets: buckets) }
      end

      def summary(name, help, labels: [], quantiles: Summary::DEFAULT_QUANTILES)
        fetch_or_create(name) { Summary.new(name: name, help: help, labels: labels, quantiles: quantiles) }
      end

      def get(name)
        @mutex.synchronize { @metrics[name] }
      end

      def to_prometheus
        @mutex.synchronize { @metrics.values.dup }.map(&:to_prometheus).join("\n\n")
      end

      def clear
        @mutex.synchronize { @metrics.clear }
      end

      def names
        @mutex.synchronize { @metrics.keys }
      end

      private

      def fetch_or_create(name)
        @mutex.synchronize do
          @metrics[name] ||= yield
        end
      end
    end
  end
end
