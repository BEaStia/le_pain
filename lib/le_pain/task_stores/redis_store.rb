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
        data = task.to_h
        @redis.multi do
          @redis.setex(task_key(task.id), @ttl, JSON.generate(data))
          @redis.zadd(INDEX_KEY, task.created_at.to_f, task.id)
        end
        task
      end

      def find(id)
        data = @redis.get(task_key(id))
        return nil unless data

        JSON.parse(data)
      end

      def update(id, &block)
        data = @redis.get(task_key(id))
        return nil unless data

        task = Task.from_hash(JSON.parse(data))
        yield task
        @redis.setex(task_key(id), @ttl, JSON.generate(task.to_h))
        task
      end

      def delete(id)
        @redis.multi do
          @redis.del(task_key(id))
          @redis.zrem(INDEX_KEY, id)
        end
      end

      def list(limit: 50, state: nil)
        ids = @redis.zrevrange(INDEX_KEY, 0, limit - 1)
        tasks = ids.map { |id| find(id) }.compact.map { |data| Task.from_hash(data) }

        tasks = tasks.select { |t| t.state == state } if state
        tasks
      end

      def cleanup
        @redis.zremrangebyscore(INDEX_KEY, 0, Time.now.to_f - @ttl)
      end

      def size
        @redis.zcard(INDEX_KEY)
      end

      def clear
        keys = @redis.keys("#{KEY_PREFIX}*")
        @redis.del(*keys) if keys.any?
        @redis.del(INDEX_KEY)
      end

      private

      def task_key(id)
        "#{KEY_PREFIX}#{id}"
      end
    end
  end
end
