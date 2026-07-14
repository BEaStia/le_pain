# frozen_string_literal: true

require_relative 'base'

module LePain
  module TaskStores
    class MemoryStore < Base
      def initialize(ttl: 86400)
        @tasks = {}
        @ttl = ttl
      end

      def create(task)
        @tasks[task.id] = task
        task
      end

      def find(id)
        task = @tasks[id]
        return nil unless task

        if task.finished? && task.updated_at < Time.now - @ttl
          @tasks.delete(id)
          return nil
        end

        task
      end

      def update(id, &block)
        task = @tasks[id]
        return nil unless task

        yield task
        task.updated_at = Time.now
        task
      end

      def delete(id)
        @tasks.delete(id)
      end

      def list(limit: 50, state: nil)
        tasks = @tasks.values
        tasks = tasks.select { |t| t.state == state } if state
        tasks.sort_by(&:created_at).reverse.first(limit)
      end

      def cleanup
        now = Time.now
        @tasks.reject! { |_id, task| task.finished? && task.updated_at < now - @ttl }
      end

      def size
        @tasks.size
      end

      def clear
        @tasks.clear
      end
    end
  end
end
