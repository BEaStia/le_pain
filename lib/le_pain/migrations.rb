# frozen_string_literal: true

module LePain
  module Migrations
    class Migration
      attr_reader :version, :name, :description

      def initialize(version:, name:, description: nil)
        @version = version
        @name = name
        @description = description
      end

      def up(connection)
        raise NotImplementedError
      end

      def down(connection)
        raise NotImplementedError
      end

      def to_h
        {
          version: @version,
          name: @name,
          description: @description,
        }
      end
    end

    class Runner
      def initialize(connection:, migrations_dir: nil)
        @connection = connection
        @migrations_dir = migrations_dir || File.join(Dir.pwd, 'db', 'migrations')
        @migrations = {}
        load_migrations
      end

      def migrate(version: nil)
        ensure_migrations_table

        applied = applied_versions
        pending = pending_migrations(applied)

        pending = pending.select { |m| m.version <= version } if version

        pending.each do |migration|
          LePain::Application.logger.info("Running migration: #{migration.version} - #{migration.name}")
          migration.up(@connection)
          record_migration(migration)
        end

        pending.size
      end

      def rollback(steps: 1)
        ensure_migrations_table

        applied = applied_versions.sort.reverse.first(steps)
        applied.each do |version|
          migration = @migrations[version]
          next unless migration

          LePain::Application.logger.info("Rolling back migration: #{version} - #{migration.name}")
          migration.down(@connection)
          remove_migration_record(version)
        end

        applied.size
      end

      def status
        ensure_migrations_table

        applied = applied_versions
        @migrations.values.sort_by(&:version).map do |migration|
          {
            version: migration.version,
            name: migration.name,
            status: applied.include?(migration.version) ? :applied : :pending,
          }
        end
      end

      def pending_count
        applied = applied_versions
        @migrations.values.count { |m| !applied.include?(m.version) }
      end

      private

      def load_migrations
        return unless File.directory?(@migrations_dir)

        Dir.glob(File.join(@migrations_dir, '*.rb')).each do |file|
          require file
        end

        ObjectSpace.each_object(Class).select { |c| c < Migration }.each do |migration_class|
          migration = migration_class.new
          @migrations[migration.version] = migration
        end
      end

      def ensure_migrations_table
        @connection.exec(<<~SQL)
          CREATE TABLE IF NOT EXISTS schema_migrations (
            version VARCHAR(255) PRIMARY KEY,
            name VARCHAR(255) NOT NULL,
            applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          )
        SQL
      end

      def applied_versions
        result = @connection.exec('SELECT version FROM schema_migrations ORDER BY version')
        result.map { |row| row['version'] }
      end

      def pending_migrations(applied)
        @migrations.values
          .reject { |m| applied.include?(m.version) }
          .sort_by(&:version)
      end

      def record_migration(migration)
        @connection.exec_params(
          'INSERT INTO schema_migrations (version, name) VALUES ($1, $2)',
          [migration.version, migration.name]
        )
      end

      def remove_migration_record(version)
        @connection.exec_params('DELETE FROM schema_migrations WHERE version = $1', [version])
      end
    end
  end
end
