# frozen_string_literal: true

require 'socket'
require 'json'

module LePain
  class HealthCheck
    attr_reader :checks
    attr_accessor :enhanced

    def initialize(enhanced: nil)
      @checks = {}
      @server_thread = nil
      @enhanced = enhanced
    end

    def register(name, &block)
      @checks[name] = block
    end

    def start(port = 3000)
      @server = TCPServer.new(port)
      @server_thread = Thread.new do
        loop do
          client = @server.accept
          handle_request(client)
        end
      end
      LePain::Application.logger.info("health check server started on port #{port}")
    end

    def stop
      @server&.close
      @server_thread&.join(1)
    end

    def status
      results = @checks.transform_values do |check|
        begin
          result = check.call
          { status: 'ok', details: result }
        rescue StandardError => e
          { status: 'error', message: e.message }
        end
      end

      overall = results.values.all? { |r| r[:status] == 'ok' } ? 'healthy' : 'unhealthy'
      { status: overall, checks: results, timestamp: Time.now.iso8601 }
    end

    private

    def handle_request(client)
      request = client.gets
      return unless request

      method, path = request.split
      if method == 'GET' && health_path?(path)
        body = status_for_path(path)
        status_code = healthy_response?(body) ? 200 : 503
        response = JSON.generate(body)
        client.print "HTTP/1.1 #{status_code} #{reason_phrase(status_code)}\r\nContent-Type: application/json\r\n\r\n#{response}"
      else
        client.print "HTTP/1.1 404 Not Found\r\n\r\n"
      end
    rescue StandardError => e
      LePain::Application.logger.error("health check error: #{e.message}")
      client.print "HTTP/1.1 500 Internal Server Error\r\n\r\n"
    ensure
      client&.close
    end

    def health_path?(path)
      ['/health', '/health/startup', '/health/readiness', '/health/liveness'].include?(path)
    end

    def status_for_path(path)
      return status unless @enhanced

      case path
      when '/health/startup'
        @enhanced.check_startup
      when '/health/readiness'
        @enhanced.check_readiness
      when '/health/liveness'
        @enhanced.check_liveness
      else
        @enhanced.check_all
      end
    end

    def healthy_response?(body)
      status = body[:status] || body['status']
      return status.to_s == 'healthy' if status

      %i[startup readiness liveness].all? do |probe|
        probe_status = body.dig(probe, :status) || body.dig(probe.to_s, 'status')
        probe_status.to_s == 'healthy'
      end
    end

    def reason_phrase(status_code)
      status_code == 200 ? 'OK' : 'Service Unavailable'
    end
  end
end
