# frozen_string_literal: true

require 'socket'
require 'json'

module LePain
  class HealthCheck
    attr_reader :checks

    def initialize
      @checks = {}
      @server_thread = nil
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

      if request.start_with?('GET /health')
        response = JSON.generate(status)
        client.print "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n#{response}"
      else
        client.print "HTTP/1.1 404 Not Found\r\n\r\n"
      end
    rescue StandardError => e
      LePain::Application.logger.error("health check error: #{e.message}")
      client.print "HTTP/1.1 500 Internal Server Error\r\n\r\n"
    ensure
      client&.close
    end
  end
end
