# frozen_string_literal: true

require 'sqlite3'
require 'json'
require_relative 'base'

module LePain
  module TaskStores
    class SqliteStore < Base
      def initialize(database: ':memory:', ttl: 86400)
        @database_path = database
        @ttl = ttl
        @db = SQLite3::Database.new(database)
        @db.results_as_hash = true
        create_table
      end

      def create(task)
        @db.execute(
          "INSERT INTO tasks (id, type, state, payload, result, error, context, created_at, updated_at, started_at, completed_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [
            task.id,
            task.type,
            task.state,
            task.payload.to_json,
            task.result&.to_json,
            task.error&.to_json,
            task.context&.to_json,
            task.created_at.to_i,
            task.updated_at.to_i,
            task.started_at&.to_i,
            task.completed_at&.to_i
          ]
        )
        task
      end

      def find(id)
        row = @db.get_first_row(
          "SELECT * FROM tasks WHERE id = ?",
          [id]
        )
        return nil unless row

        task = row_to_task(row)

        # Проверяем TTL для завершенных задач
        if task.finished? && task.updated_at < Time.now - @ttl
          delete(id)
          return nil
        end

        task
      end

      def update(id)
        row = @db.get_first_row(
          "SELECT * FROM tasks WHERE id = ?",
          [id]
        )
        return nil unless row

        task = row_to_task(row)
        yield task

        @db.execute(
          "UPDATE tasks SET state = ?, result = ?, error = ?, updated_at = ?, completed_at = ? WHERE id = ?",
          [
            task.state,
            task.result&.to_json,
            task.error&.to_json,
            task.updated_at.to_i,
            task.completed_at&.to_i,
            id
          ]
        )

        task
      end

      def list(limit: 50, state: nil, type: nil)
        query = "SELECT * FROM tasks WHERE 1=1"
        params = []

        if state
          query += " AND state = ?"
          params << state
        end

        if type
          query += " AND type = ?"
          params << type
        end

        query += " ORDER BY created_at DESC LIMIT ?"
        params << limit

        rows = @db.execute(query, params)
        rows.map { |row| row_to_task(row) }
      end

      def delete(id)
        @db.execute("DELETE FROM tasks WHERE id = ?", [id])
      end

      def cleanup
        cutoff = (Time.now - @ttl).to_i
        @db.execute(
          "DELETE FROM tasks WHERE state IN ('completed', 'failed', 'cancelled') AND updated_at < ?",
          [cutoff]
        )
      end

      def size
        result = @db.get_first_value("SELECT COUNT(*) FROM tasks")
        result.to_i
      end

      def clear
        @db.execute("DELETE FROM tasks")
      end

      def close
        @db.close
      end

      private

      def create_table
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            state TEXT NOT NULL DEFAULT 'pending',
            payload TEXT,
            result TEXT,
            error TEXT,
            context TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            started_at INTEGER,
            completed_at INTEGER
          )
        SQL

        @db.execute("CREATE INDEX IF NOT EXISTS idx_tasks_state ON tasks(state)")
        @db.execute("CREATE INDEX IF NOT EXISTS idx_tasks_type ON tasks(type)")
        @db.execute("CREATE INDEX IF NOT EXISTS idx_tasks_created ON tasks(created_at)")
      end

      def row_to_task(row)
        LePain::Task.new(
          id: row['id'],
          type: row['type'],
          state: row['state'],
          payload: row['payload'] ? JSON.parse(row['payload']) : {},
          result: row['result'] ? JSON.parse(row['result']) : nil,
          error: row['error'] ? JSON.parse(row['error']) : nil,
          context: row['context'] ? JSON.parse(row['context']) : nil,
          created_at: Time.at(row['created_at']),
          updated_at: Time.at(row['updated_at']),
          started_at: row['started_at'] ? Time.at(row['started_at']) : nil,
          completed_at: row['completed_at'] ? Time.at(row['completed_at']) : nil
        )
      end
    end
  end
end
