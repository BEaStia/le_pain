# frozen_string_literal: true

require 'socket'
require 'json'
require 'uri'

module LePain
  module Transports
    class HttpAdapter
      attr_reader :router, :port

      def initialize(router:, port: 3000)
        @router = router
        @port = port
        @server = nil
        @thread = nil
      end

      def start
        @server = TCPServer.new(@port)
        @thread = Thread.new { run }
        LePain::Application.logger.info("http transport started on port #{@port}")
      end

      def stop
        @server&.close
        @thread&.kill
      end

      private

      def run
        loop do
          client = @server.accept
          Thread.new { handle_client(client) }
        end
      end

      def handle_client(client)
        request_line = client.gets
        return unless request_line

        method, path, _version = request_line.split(' ')
        headers = read_headers(client)
        body = read_body(client, headers)

        query = {}
        path, query_string = path.split('?', 2)
        if query_string
          URI.decode_www_form(query_string).each { |k, v| query[k] = v }
        end

        lepain_request = LePain::Request.from_http(
          method: method,
          path: path,
          body: parse_body(body),
          headers: headers,
          query: query,
        )
        lepain_request.instance_variable_set(:@path_params, {})

        response = @router.dispatch(lepain_request)
        send_response(client, response)
      rescue StandardError => e
        LePain::Application.logger.error("http error: #{e.message}")
        send_response(client, LePain::Response.error('internal server error', status: 500))
      ensure
        client&.close
      end

      def read_headers(client)
        headers = {}
        loop do
          line = client.gets
          break if line.nil? || line.strip.empty?

          key, value = line.split(':', 2)
          headers[key.strip.downcase] = value.strip if key && value
        end
        headers
      end

      def read_body(client, headers)
        length = headers['content-length']&.to_i
        return '' unless length && length > 0

        client.read(length)
      end

      def parse_body(body)
        return {} if body.nil? || body.empty?

        JSON.parse(body)
      rescue JSON::ParserError
        { raw: body }
      end

      def send_response(client, response)
        body = response.to_json
        status_text = case response.status
                      when 200 then 'OK'
                      when 201 then 'Created'
                      when 400 then 'Bad Request'
                      when 404 then 'Not Found'
                      when 500 then 'Internal Server Error'
                      else 'Unknown'
                      end

        client.print "HTTP/1.1 #{response.status} #{status_text}\r\n"
        client.print "Content-Type: application/json\r\n"
        client.print "Content-Length: #{body.bytesize}\r\n"
        client.print "\r\n"
        client.print body
      end
    end
  end
end
