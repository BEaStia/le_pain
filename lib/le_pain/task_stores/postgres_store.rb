# frozen_string_literal: true

require_relative 'base'

module LePain
  module TaskStores
    class PostgresStore < Base
      def initialize(connection_string: nil, connection: nil, pool_size: 5, ttl: 86400, cleanup_interval: nil)
        require 'pg'

        @ttl = ttl
        @connection_string = connection_string
        @pool_size = pool_size
        @connection = connection
        @pool = []
        @mutex = Mutex.new
        @cleanup_interval = cleanup_interval
        @cleanup_thread = nil
        @stop_cleanup = false

        ensure_schema if @connection || @connection_string
        start_cleanup_scheduler if @cleanup_interval
      end

      def create(task)
        with_connection do |conn|
          conn.exec_params(
            <<~SQL,
              INSERT INTO lepain_tasks (id, type, state, payload, result, error, context, created_at, updated_at, started_at, completed_at, attempts)
              VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
              RETURNING *
            SQL
            [
              task.id,
              task.type,
              task.state,
              JSON.generate(task.payload),
              task.result ? JSON.generate(task.result) : nil,
              task.error ? JSON.generate(task.error) : nil,
              task.context ? JSON.generate(task.context) : nil,
              task.created_at,
              task.updated_at,
              task.started_at,
              task.completed_at,
              task.attempts,
            ]
          )
        end
        task
      end

      def find(id)
        with_connection do |conn|
          result = conn.exec_params(
            'SELECT * FROM lepain_tasks WHERE id = $1',
            [id]
          )
          return nil if result.ntuples.zero?

          row = result.first
          task = row_to_task(row)

          if task.finished? && task.updated_at < Time.now - @ttl
            delete(id)
            return nil
          end

          task
        end
      end

      def update(id, &block)
        with_connection do |conn|
          transaction(conn) do
            result = conn.exec_params('SELECT * FROM lepain_tasks WHERE id = $1 FOR UPDATE', [id])
            next nil if result.ntuples.zero?

            task = row_to_task(result.first)
            yield task

            conn.exec_params(
              <<~SQL,
                UPDATE lepain_tasks
                SET state = $2, result = $3, error = $4, updated_at = $5, completed_at = $6,
                    started_at = $7, attempts = $8
                WHERE id = $1
              SQL
              [
                id,
                task.state,
                task.result ? JSON.generate(task.result) : nil,
                task.error ? JSON.generate(task.error) : nil,
                Time.now,
                task.completed_at,
                task.started_at,
                task.attempts,
              ]
            )
            task
          end
        end
      end

      def list(limit: 50, state: nil, type: nil, offset: nil, page: nil, page_size: nil, search: nil)
        with_connection do |conn|
          conditions = []
          params = []
          param_idx = 1

          if state
            conditions << "state = $#{param_idx}"
            params << state
            param_idx += 1
          end

          if type
            conditions << "type = $#{param_idx}"
            params << type
            param_idx += 1
          end

          if search
            conditions << "to_tsvector('simple', coalesce(payload::text, '')) @@ plainto_tsquery('simple', $#{param_idx})"
            params << search
            param_idx += 1
          end

          effective_limit = (page_size || limit).to_i
          effective_offset = offset || (page ? [(page.to_i - 1), 0].max * effective_limit : 0)

          where_clause = conditions.any? ? "WHERE #{conditions.join(' AND ')}" : ''
          params << effective_limit
          params << effective_offset

          result = conn.exec_params(
            "SELECT * FROM lepain_tasks #{where_clause} ORDER BY created_at DESC LIMIT $#{param_idx} OFFSET $#{param_idx + 1}",
            params
          )

          result.map { |row| row_to_task(row) }
        end
      end

      def delete(id)
        with_connection do |conn|
          conn.exec_params('DELETE FROM lepain_tasks WHERE id = $1', [id])
        end
      end

      def cleanup
        with_connection do |conn|
          conn.exec_params(
            "DELETE FROM lepain_tasks WHERE state IN ('completed', 'failed', 'cancelled') AND updated_at < $1",
            [Time.now - @ttl]
          )
        end
      end

      def size
        with_connection do |conn|
          result = conn.exec('SELECT COUNT(*) as count FROM lepain_tasks')
          result.first['count'].to_i
        end
      end

      def clear
        with_connection do |conn|
          conn.exec('DELETE FROM lepain_tasks')
        end
      end

      def start_cleanup_scheduler
        return if @cleanup_thread&.alive?

        @stop_cleanup = false
        @cleanup_thread = Thread.new do
          until @stop_cleanup
            begin
              sleep @cleanup_interval
              cleanup
            rescue StandardError => e
              LePain::Application.logger.error("postgres task cleanup failed: #{e.message}")
            end
          end
        end
      end

      def stop_cleanup_scheduler
        @stop_cleanup = true
        @cleanup_thread&.kill
        @cleanup_thread = nil
      end

      private

      def transaction(conn)
        conn.exec('BEGIN')
        result = yield
        conn.exec('COMMIT')
        result
      rescue StandardError
        conn.exec('ROLLBACK')
        raise
      end

      def with_connection(&block)
        conn = acquire_connection
        begin
          yield conn
        ensure
          release_connection(conn)
        end
      end

      def acquire_connection
        @mutex.synchronize do
          if @pool.any?
            return @pool.pop
          end
        end

        if @connection
          @connection
        else
          PG.connect(@connection_string)
        end
      end

      def release_connection(conn)
        return if @connection # Don't pool external connection

        @mutex.synchronize do
          @pool << conn if @pool.size < @pool_size
        end
      end

      def ensure_schema
        with_connection do |conn|
          conn.exec(<<~SQL)
            CREATE TABLE IF NOT EXISTS lepain_tasks (
              id UUID PRIMARY KEY,
              type VARCHAR NOT NULL,
              state VARCHAR NOT NULL DEFAULT 'pending',
              payload JSONB,
              result JSONB,
              error JSONB,
              context JSONB,
              created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
              updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
              started_at TIMESTAMPTZ,
              completed_at TIMESTAMPTZ,
              attempts INTEGER DEFAULT 0
            );

            ALTER TABLE lepain_tasks ADD COLUMN IF NOT EXISTS attempts INTEGER DEFAULT 0;

            CREATE INDEX IF NOT EXISTS idx_lepain_tasks_state ON lepain_tasks(state);
            CREATE INDEX IF NOT EXISTS idx_lepain_tasks_type ON lepain_tasks(type);
            CREATE INDEX IF NOT EXISTS idx_lepain_tasks_created ON lepain_tasks(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_lepain_tasks_payload_gin ON lepain_tasks USING GIN (payload);
            CREATE INDEX IF NOT EXISTS idx_lepain_tasks_payload_fts ON lepain_tasks USING GIN (to_tsvector('simple', coalesce(payload::text, '')));
          SQL
        end
      end

      def row_to_task(row)
        Task.from_hash({
          'id' => row['id'],
          'type' => row['type'],
          'state' => row['state'],
          'payload' => row['payload'] ? JSON.parse(row['payload']) : {},
          'result' => row['result'] ? JSON.parse(row['result']) : nil,
          'error' => row['error'] ? JSON.parse(row['error']) : nil,
          'context' => row['context'] ? JSON.parse(row['context']) : nil,
          'created_at' => row['created_at'].to_s,
          'updated_at' => row['updated_at'].to_s,
          'started_at' => row['started_at']&.to_s,
          'completed_at' => row['completed_at']&.to_s,
          'attempts' => row['attempts'].to_i,
        })
      end
    end
  end
end
