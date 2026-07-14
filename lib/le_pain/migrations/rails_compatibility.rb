# frozen_string_literal: true

module LePain
  module Migrations
    module RailsCompatibility
      # Конвертер Rails миграций в LePain миграции
      class RailsMigrationConverter
        def self.convert(rails_migration_path, output_path)
          content = File.read(rails_migration_path)
          
          # Извлекаем класс и версию
          class_name = content.match(/class\s+(\w+)\s*</)[1]
          version = File.basename(rails_migration_path).split('_').first
          
          # Извлекаем up/down методы
          up_method = extract_method(content, :up)
          down_method = extract_method(content, :down)
          
          # Генерируем LePain миграцию
          template = <<~RUBY
            # frozen_string_literal: true

            class #{class_name} < LePain::Migrations::Migration
              version '#{version}'
              name '#{underscore(class_name)}'
              description 'Converted from Rails migration'

              def up(connection)
                #{convert_rails_dsl(up_method)}
              end

              def down(connection)
                #{convert_rails_dsl(down_method)}
              end
            end
          RUBY

          File.write(output_path, template)
        end

        def self.extract_method(content, method_name)
          match = content.match(/def\s+#{method_name}\s*\n(.*?)\n\s*end/m)
          match ? match[1].strip : ''
        end

        def self.convert_rails_dsl(code)
          # Простая конвертация Rails DSL в LePain DSL
          # Это базовая реализация, можно расширять
          code
            .gsub(/create_table\s+:(\w+)\s+do\s*\|t\|/, 'adapter.create_table(:\1) do |t|')
            .gsub(/t\.(string|text|integer|boolean|datetime|timestamp|json|uuid)\s+:(\w+)/, 't.\1 :\2')
            .gsub(/add_index\s+:(\w+),\s+:(\w+)/, 'adapter.add_index(:\1, :\2)')
            .gsub(/add_column\s+:(\w+),\s+:(\w+),\s+:(\w+)/, 'adapter.add_column(:\1, :\2, :\3)')
            .gsub(/remove_column\s+:(\w+),\s+:(\w+)/, 'adapter.remove_column(:\1, :\2)')
            .gsub(/drop_table\s+:(\w+)/, 'adapter.drop_table(:\1)')
            .gsub(/execute\s+["'](.+?)["']/, 'adapter.execute("\1")')
        end

        def self.underscore(camel_case)
          camel_case.gsub(/::/, '/')
                    .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                    .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                    .tr('-', '_')
                    .downcase
        end
      end

      # Раннер для запуска Rails миграций через ActiveRecord
      class RailsMigrationRunner
        def initialize(config = {})
          @config = config
          setup_active_record
        end

        def migrate(version: nil)
          if version
            ActiveRecord::Migrator.migrate(migrations_path, version)
          else
            ActiveRecord::Migrator.migrate(migrations_path)
          end
        end

        def rollback(steps: 1)
          ActiveRecord::Migrator.rollback(migrations_path, steps)
        end

        def status
          ActiveRecord::Migrator.get_all_versions(migrations_path)
        end

        private

        def setup_active_record
          require 'active_record'
          
          ActiveRecord::Base.establish_connection(@config)
          
          # Создаем таблицу schema_migrations если её нет
          unless ActiveRecord::Base.connection.table_exists?(:schema_migrations)
            ActiveRecord::Schema.define do
              create_table :schema_migrations, id: false do |t|
                t.string :version, null: false
                t.index :version, unique: true
              end
            end
          end
        end

        def migrations_path
          @config[:migrations_path] || File.join(Dir.pwd, 'db', 'migrate')
        end
      end

      # Адаптер для использования ActiveRecord connection в LePain миграциях
      class ActiveRecordAdapter < Adapters::Base
        def create_table(name, &block)
          connection.create_table(name, &block)
        end

        def drop_table(name)
          connection.drop_table(name)
        end

        def add_column(table, name, type, options = {})
          connection.add_column(table, name, type, **options)
        end

        def remove_column(table, name)
          connection.remove_column(table, name)
        end

        def add_index(table, columns, options = {})
          connection.add_index(table, columns, **options)
        end

        def remove_index(table, columns)
          connection.remove_index(table, columns)
        end

        def execute(sql)
          connection.execute(sql)
        end

        def table_exists?(name)
          connection.table_exists?(name)
        end

        def column_exists?(table, column)
          connection.column_exists?(table, column)
        end
      end
    end
  end
end
