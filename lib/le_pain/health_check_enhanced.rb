# frozen_string_literal: true

module LePain
  module HealthCheckEnhanced
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
