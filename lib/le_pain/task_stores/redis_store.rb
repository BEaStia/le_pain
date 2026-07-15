# frozen_string_literal: true

require 'json'
require_relative 'base'

module LePain
  module TaskStores
    class RedisStore < Base
      KEY_PREFIX = 'lepain:task:'
      INDEX_KEY = 'lepain:tasks:index'

      def initialize(redis:, ttl: 86400)
        @redis = redis
        @ttl = ttl
      end

      def create(task)
        with_circuit_breaker do
          data = task.to_h
          @redis.multi do
            @redis.setex(task_key(task.id), @ttl, JSON.generate(data))
            @redis.zadd(INDEX_KEY, task.created_at.to_f, task.id)
          end
          task
        end
      end

      def find(id)
        with_circuit_breaker do
          data = @redis.get(task_key(id))
          return nil unless data

          JSON.parse(data)
        end
      end

      def update(id, &block)
        with_circuit_breaker do
          data = @redis.get(task_key(id))
          return nil unless data

          task = Task.from_hash(JSON.parse(data))
          yield task
          @redis.setex(task_key(id), @ttl, JSON.generate(task.to_h))
          task
        end
      end

      def delete(id)
        with_circuit_breaker do
          @redis.multi do
            @redis.del(task_key(id))
            @redis.zrem(INDEX_KEY, id)
          end
        end
      end

      def list(limit: 50, state: nil)
        with_circuit_breaker do
          ids = @redis.zrevrange(INDEX_KEY, 0, limit - 1)
          tasks = ids.map { |id| find(id) }.compact.map { |data| Task.from_hash(data) }

          tasks = tasks.select { |t| t.state == state } if state
          tasks
        end
      end

      def cleanup
        with_circuit_breaker { @redis.zremrangebyscore(INDEX_KEY, 0, Time.now.to_f - @ttl) }
      end

      def size
        with_circuit_breaker { @redis.zcard(INDEX_KEY) }
      end

      def clear
        with_circuit_breaker do
          keys = @redis.keys("#{KEY_PREFIX}*")
          @redis.del(*keys) if keys.any?
          @redis.del(INDEX_KEY)
        end
      end

      private

      def with_circuit_breaker(&block)
        CircuitBreaker.get('redis_task_store').call(&block)
      end

      def task_key(id)
        "#{KEY_PREFIX}#{id}"
      end
    end
  end
end
