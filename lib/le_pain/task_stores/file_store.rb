# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'base'

module LePain
  module TaskStores
    class FileStore < Base
      def initialize(path: '/tmp/lepain_tasks', ttl: 86400)
        @path = path
        @ttl = ttl
        FileUtils.mkdir_p(@path)
      end

      def create(task)
        write(task.id, task.to_h)
        task
      end

      def find(id)
        data = read(id)
        return nil unless data

        task = Task.from_hash(data)

        if task.finished? && task.updated_at < Time.now - @ttl
          delete(id)
          return nil
        end

        task
      end

      def update(id, &block)
        data = read(id)
        return nil unless data

        task = Task.from_hash(data)
        yield task
        write(task.id, task.to_h)
        task
      end

      def delete(id)
        file = task_path(id)
        File.delete(file) if File.exist?(file)
      end

      def list(limit: 50, state: nil)
        files = Dir.glob(File.join(@path, '*.json'))
        tasks = files.map { |f| read(File.basename(f, '.json')) }.compact.map { |data| Task.from_hash(data) }

        tasks = tasks.select { |t| t.state == state } if state
        tasks.sort_by(&:created_at).reverse.first(limit)
      end

      def cleanup
        now = Time.now
        Dir.glob(File.join(@path, '*.json')).each do |file|
          data = read(File.basename(file, '.json'))
          next unless data

          task = Task.from_hash(data)
          delete(task.id) if task.finished? && task.updated_at < now - @ttl
        end
      end

      def size
        Dir.glob(File.join(@path, '*.json')).size
      end

      def clear
        FileUtils.rm_rf(@path)
        FileUtils.mkdir_p(@path)
      end

      private

      def task_path(id)
        File.join(@path, "#{id}.json")
      end

      def read(id)
        path = task_path(id)
        return nil unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        nil
      end

      def write(id, data)
        File.write(task_path(id), JSON.generate(data))
      end

    end
  end
end
