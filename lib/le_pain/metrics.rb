# frozen_string_literal: true

require_relative 'metrics/registry'

module LePain
  module Metrics
    class << self
      def registry
        @registry ||= Registry.new.tap { |r| register_builtins(r) }
      end

      def counter(name, help, labels: [])
        registry.counter(name, help, labels: labels)
      end

      def gauge(name, help, labels: [])
        registry.gauge(name, help, labels: labels)
      end

      def histogram(name, help, labels: [], buckets: Metrics::Histogram::DEFAULT_BUCKETS)
        registry.histogram(name, help, labels: labels, buckets: buckets)
      end

      def summary(name, help, labels: [], quantiles: Metrics::Summary::DEFAULT_QUANTILES)
        registry.summary(name, help, labels: labels, quantiles: quantiles)
      end

      def to_prometheus
        collect_runtime_metrics
        registry.to_prometheus
      end

      def track_http_request(method:, path:, status:, duration:)
        counter('http_requests_total', 'Total HTTP requests', labels: %w[method path status])
          .increment({ 'method' => method, 'path' => path, 'status' => status.to_s })
        histogram('http_request_duration_seconds', 'HTTP request duration', labels: %w[method path])
          .observe(duration, { 'method' => method, 'path' => path })
      end

      def track_mq_message(topic:, status:, duration:)
        counter('mq_messages_total', 'Total MQ messages', labels: %w[topic status])
          .increment({ 'topic' => topic, 'status' => status })
        histogram('mq_message_duration_seconds', 'MQ message processing duration', labels: ['topic'])
          .observe(duration, { 'topic' => topic })
      end

      def track_job(type:, status:, duration:)
        counter('jobs_total', 'Total async jobs', labels: %w[type status])
          .increment({ 'type' => type, 'status' => status })
        histogram('job_duration_seconds', 'Job execution duration', labels: ['type'])
          .observe(duration, { 'type' => type })
      end

      def active_jobs=(count)
        gauge('active_jobs', 'Number of currently running jobs').set(count)
      end

      def increment_active_jobs
        gauge('active_jobs', 'Number of currently running jobs').increment
      end

      def decrement_active_jobs
        gauge('active_jobs', 'Number of currently running jobs').decrement
      end

      private

      def register_builtins(registry)
        registry.counter('http_requests_total', 'Total HTTP requests', labels: %w[method path status])
        registry.histogram('http_request_duration_seconds', 'HTTP request duration', labels: %w[method path])
        registry.counter('mq_messages_total', 'Total MQ messages', labels: %w[topic status])
        registry.histogram('mq_message_duration_seconds', 'MQ message processing duration', labels: ['topic'])
        registry.counter('jobs_total', 'Total async jobs', labels: %w[type status])
        registry.histogram('job_duration_seconds', 'Job execution duration', labels: ['type'])
        registry.gauge('active_jobs', 'Number of currently running jobs')
        registry.gauge('process_uptime_seconds', 'Process uptime in seconds')
        registry.gauge('process_memory_bytes', 'Process memory usage in bytes')
        registry.gauge('metrics_registered_total', 'Number of registered metrics')
      end

      def collect_runtime_metrics
        @started_at ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
        gauge('process_uptime_seconds', 'Process uptime in seconds').set(
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at
        )
        gauge('process_memory_bytes', 'Process memory usage in bytes').set(current_memory_bytes)
        gauge('metrics_registered_total', 'Number of registered metrics').set(registry.names.size)
      end

      def current_memory_bytes
        pages = `ps -o rss= -p #{Process.pid}`.to_i
        pages * 1024
      rescue StandardError
        0
      end
    end
  end
end
