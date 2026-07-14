# frozen_string_literal: true

module LePain
  module Transports
    class MqAdapter
      attr_reader :router, :client

      def initialize(router:, client:)
        @router = router
        @client = client
        @running = false
      end

      def subscribe(topic, &block)
        @client.subscribe(topic) do |message|
          request = LePain::Request.from_mq(
            topic: topic,
            message: message,
            metadata: { consumer: self.class.name },
          )
          response = @router.dispatch(request)
          block.call(response) if block
        end
      end

      def start
        @running = true
        LePain::Application.logger.info('mq transport started')
      end

      def stop
        @running = false
        @client&.close
      end
    end

    class MqClient
      def subscribe(topic, &block)
        raise NotImplementedError, 'implement in subclass'
      end

      def publish(topic, message)
        raise NotImplementedError, 'implement in subclass'
      end

      def close; end
    end
  end
end
