# frozen_string_literal: true

require 'json'

module LePain
  class MetricsHandler
    class << self
      attr_accessor :auth_token

      def handle_request(request, context)
        case request.action
        when 'GET:/metrics'
          return Response.unauthorized('metrics token is invalid') unless authorized?(request)

          Response.new(status: 200, body: LePain::Metrics.to_prometheus, headers: { 'Content-Type' => 'text/plain; version=0.0.4; charset=utf-8' })
        else
          Response.not_found("no route for #{request.action}")
        end
      rescue StandardError => e
        LePain::Application.logger.error("metrics handler error: #{e.message}")
        Response.error('internal server error', status: 500)
      end

      private

      def authorized?(request)
        return true unless auth_token

        token = request.headers['authorization']&.sub(/\ABearer\s+/i, '') ||
                request.headers['x-metrics-token'] ||
                request['auth_token']
        token == auth_token
      end
    end
  end
end
