# frozen_string_literal: true

module LePain
  module Transports
    class KafkaClient < MqClient
      def initialize(brokers:, group_id:)
        @brokers = brokers
        @group_id = group_id
      end

      def subscribe(topic, &block)
        LePain::Application.logger.info("kafka subscribing to #{topic}")
      end

      def publish(topic, message)
        CircuitBreaker.get('kafka').call do
          LePain::Application.logger.info("kafka publishing to #{topic}")
        end
      end
    end

    class NatsClient < MqClient
      def initialize(url:)
        @url = url
      end

      def subscribe(topic, &block)
        LePain::Application.logger.info("nats subscribing to #{topic}")
      end

      def publish(topic, message)
        CircuitBreaker.get('nats').call do
          LePain::Application.logger.info("nats publishing to #{topic}")
        end
      end
    end

    class RmqClient < MqClient
      def initialize(url:)
        @url = url
      end

      def subscribe(topic, &block)
        LePain::Application.logger.info("rmq subscribing to #{topic}")
      end

      def publish(topic, message)
        CircuitBreaker.get('rmq').call do
          LePain::Application.logger.info("rmq publishing to #{topic}")
        end
      end
    end
  end
end
