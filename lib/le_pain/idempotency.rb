# frozen_string_literal: true

module LePain
  module Idempotency
    class Store
      def initialize(ttl: 3600)
        @cache = {}
        @ttl = ttl
      end

      def get(key)
        entry = @cache[key]
        return nil unless entry

        if entry[:expires_at] < Time.now
          @cache.delete(key)
          return nil
        end

        entry[:response]
      end

      def set(key, response)
        @cache[key] = {
          response: response,
          expires_at: Time.now + @ttl,
        }
      end

      def delete(key)
        @cache.delete(key)
      end

      def clear
        @cache.clear
      end
    end

    module Middleware
      def self.new(store: nil, key_extractor: nil, ttl: 3600)
        @store = store || Store.new(ttl: ttl)
        @key_extractor = key_extractor || ->(request, _context) { request.headers['idempotency-key'] || request['idempotency_key'] }

        ->(request, context) do
          return nil unless context.idempotency_key || @key_extractor

          key = context.idempotency_key || @key_extractor.call(request, context)
          return nil if key.nil? || key.empty?

          cached = @store.get(key)
          if cached
            LePain::Application.logger.info("[#{context.request_id}] idempotent hit for #{key}")
            return cached
          end

          nil
        end
      end

      def self.after_handler(key, response)
        return unless key && !key.empty?

        @store&.set(key, response)
      end

      def self.store
        @store
      end
    end
  end
end
