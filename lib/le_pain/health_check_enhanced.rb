# frozen_string_literal: true

require 'net/http'
require 'timeout'
require 'uri'

module LePain
  module HealthCheckEnhanced
    module DependencyChecks
      module_function

      def database(connection, timeout: 2)
        timeout_check(timeout) do
          if connection.respond_to?(:exec)
            connection.exec('SELECT 1')
          elsif connection.respond_to?(:execute)
            connection.execute('SELECT 1')
          elsif connection.respond_to?(:ping)
            connection.ping
          else
            raise ArgumentError, 'database connection must respond to exec, execute, or ping'
          end

          { connected: true }
        end
      end

      def redis(client, timeout: 2)
        timeout_check(timeout) do
          result = client.ping
          raise 'redis ping failed' unless result == true || result.to_s.upcase == 'PONG'

          { connected: true }
        end
      end

      def mq(client, timeout: 2)
        timeout_check(timeout) do
          if client.respond_to?(:healthy?)
            raise 'mq client unhealthy' unless client.healthy?
          elsif client.respond_to?(:connected?)
            raise 'mq client disconnected' unless client.connected?
          else
            raise ArgumentError, 'mq client must respond to healthy? or connected?'
          end

          { connected: true }
        end
      end

      def external_api(url, timeout: 2)
        timeout_check(timeout) do
          uri = URI(url)
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: timeout, read_timeout: timeout) do |http|
            http.get(uri.request_uri.empty? ? '/' : uri.request_uri)
          end

          raise "external API returned #{response.code}" unless response.code.to_i < 500

          { status: response.code.to_i }
        end
      end

      def deadlock(timeout: 1)
        timeout_check(timeout) do
          Thread.pass
          { alive_threads: Thread.list.count(&:alive?) }
        end
      end

      def timeout_check(timeout)
        Timeout.timeout(timeout) { yield }
      rescue Timeout::Error
        raise "health check timed out after #{timeout}s"
      end
    end

    class Probe
      attr_reader :name, :checks, :status, :last_checked_at

      def initialize(name)
        @name = name
        @checks = []
        @status = :unknown
        @last_checked_at = nil
      end

      def add_check(name, &block)
        @checks << { name: name, block: block }
      end

      def run
        @last_checked_at = Time.now
        results = @checks.map do |check|
          begin
            result = check[:block].call
            { name: check[:name], status: :ok, details: result }
          rescue StandardError => e
            { name: check[:name], status: :error, message: e.message }
          end
        end

        @status = results.all? { |r| r[:status] == :ok } ? :healthy : :unhealthy
        { name: @name, status: @status, checks: results, checked_at: @last_checked_at.iso8601 }
      end

      def healthy?
        @status == :healthy
      end

      def unhealthy?
        @status == :unhealthy
      end
    end

    class EnhancedHealthCheck
      attr_reader :startup_probe, :readiness_probe, :liveness_probe

      def initialize
        @startup_probe = Probe.new(:startup)
        @readiness_probe = Probe.new(:readiness)
        @liveness_probe = Probe.new(:liveness)
        @started = false
      end

      def startup(&block)
        @startup_probe.add_check(:startup, &block)
      end

      def readiness(name = :default, &block)
        @readiness_probe.add_check(name, &block)
      end

      def liveness(name = :default, &block)
        @liveness_probe.add_check(name, &block)
      end

      def database(connection, name: :database, timeout: 2)
        readiness(name) { DependencyChecks.database(connection, timeout: timeout) }
      end

      def redis(client, name: :redis, timeout: 2)
        readiness(name) { DependencyChecks.redis(client, timeout: timeout) }
      end

      def mq(client, name: :mq, timeout: 2)
        readiness(name) { DependencyChecks.mq(client, timeout: timeout) }
      end

      def external_api(url, name: :external_api, timeout: 2)
        readiness(name) { DependencyChecks.external_api(url, timeout: timeout) }
      end

      def deadlock_check(name: :deadlock, timeout: 1)
        liveness(name) { DependencyChecks.deadlock(timeout: timeout) }
      end

      def start!
        @started = true
        @startup_probe.run
      end

      def started?
        @started
      end

      def check_startup
        @startup_probe.run
      end

      def check_readiness
        return { status: :unhealthy, message: 'Service not started' } unless @started

        @readiness_probe.run
      end

      def check_liveness
        @liveness_probe.run
      end

      def check_all
        {
          startup: check_startup,
          readiness: check_readiness,
          liveness: check_liveness,
          timestamp: Time.now.iso8601,
        }
      end

      def to_h
        check_all
      end

      def to_json(*args)
        to_h.to_json(*args)
      end
    end
  end
end
