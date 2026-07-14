# frozen_string_literal: true

require 'json'

module LePain
  module Logging
    class JsonFormatter
      def initialize
        @hostname = Socket.gethostname rescue 'unknown'
        @service_name = ENV.fetch('SERVICE_NAME', 'le_pain')
      end

      def call(severity, datetime, _progname, msg)
        entry = {
          timestamp: datetime.iso8601(3),
          level: severity.downcase,
          service: @service_name,
          hostname: @hostname,
          message: extract_message(msg),
        }

        context = Context.current
        if context
          entry[:request_id] = context.request_id
          entry[:trace_id] = context.trace_id
          entry[:correlation_id] = context.correlation_id
          entry[:transport] = context.transport.to_s
        end

        if msg.is_a?(Hash) && msg[:extra]
          entry.merge!(msg[:extra])
        end

        JSON.generate(entry) + "\n"
      end

      private

      def extract_message(msg)
        case msg
        when Hash
          msg[:message] || msg['message'] || msg.to_s
        when String
          msg
        else
          msg.to_s
        end
      end
    end
  end
end
