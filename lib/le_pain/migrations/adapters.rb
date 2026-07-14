# frozen_string_literal: true

module LePain
  module Migrations
    module Adapters
      class Base
        attr_reader :connection

        def initialize(connection)
          @connection = connection
        end

        def create_table(name, &block)
          raise NotImplementedError
        end

        def drop_table(name)
          raise NotImplementedError
        end

        def add_column(table, name, type, options = {})
          raise NotImplementedError
        end

        def remove_column(table, name)
          raise NotImplementedError
        end

        def add_index(table, columns, options = {})
          raise NotImplementedError
        end

        def remove_index(table, columns)
          raise NotImplementedError
        end

        def execute(sql)
          raise NotImplementedError
        end

        def table_exists?(name)
          raise NotImplementedError
        end

        def column_exists?(table, column)
          raise NotImplementedError
        end
      end

      class PostgresAdapter < Base
        def create_table(name, &block)
          builder = TableBuilder.new(name, self)
          builder.instance_eval(&block)
          execute(builder.to_sql)
        end

        def drop_table(name)
          execute("DROP TABLE IF EXISTS #{name}")
        end

        def add_column(table, name, type, options = {})
          sql = "ALTER TABLE #{table} ADD COLUMN #{name} #{type_to_sql(type)}"
          sql += " NOT NULL" if options[:null] == false
          sql += " DEFAULT #{quote(options[:default])}" if options.key?(:default)
          execute(sql)
        end

        def remove_column(table, name)
          execute("ALTER TABLE #{table} DROP COLUMN #{name}")
        end

        def add_index(table, columns, options = {})
          columns = Array(columns)
          index_name = options[:name] || "#{table}_#{columns.join('_')}_index"
          unique = options[:unique] ? "UNIQUE " : ""
          execute("CREATE #{unique}INDEX #{index_name} ON #{table} (#{columns.join(', ')})")
        end

        def remove_index(table, columns)
          columns = Array(columns)
          index_name = "#{table}_#{columns.join('_')}_index"
          execute("DROP INDEX IF EXISTS #{index_name}")
        end

        def execute(sql)
          connection.exec(sql)
        end

        def table_exists?(name)
          result = connection.exec_params(
            "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = $1)",
            [name.to_s]
          )
          result[0]['exists'] == 't'
        end

        def column_exists?(table, column)
          result = connection.exec_params(
            "SELECT EXISTS (SELECT FROM information_schema.columns WHERE table_name = $1 AND column_name = $2)",
            [table.to_s, column.to_s]
          )
          result[0]['exists'] == 't'
        end

        private

        def type_to_sql(type)
          case type.to_s
          when 'string' then 'VARCHAR(255)'
          when 'text' then 'TEXT'
          when 'integer' then 'INTEGER'
          when 'bigint' then 'BIGINT'
          when 'float' then 'FLOAT'
          when 'decimal' then 'DECIMAL'
          when 'boolean' then 'BOOLEAN'
          when 'date' then 'DATE'
          when 'datetime', 'timestamp' then 'TIMESTAMP'
          when 'json' then 'JSONB'
          when 'uuid' then 'UUID'
          else type.to_s.upcase
          end
        end

        def quote(value)
          case value
          when nil then 'NULL'
          when true then 'TRUE'
          when false then 'FALSE'
          when Numeric then value.to_s
          else "'#{value}'"
          end
        end
      end

      class MySQLAdapter < Base
        def create_table(name, &block)
          builder = TableBuilder.new(name, self)
          builder.instance_eval(&block)
          execute(builder.to_sql)
        end

        def drop_table(name)
          execute("DROP TABLE IF EXISTS #{name}")
        end

        def add_column(table, name, type, options = {})
          sql = "ALTER TABLE #{table} ADD COLUMN #{name} #{type_to_sql(type)}"
          sql += " NOT NULL" if options[:null] == false
          sql += " DEFAULT #{quote(options[:default])}" if options.key?(:default)
          execute(sql)
        end

        def remove_column(table, name)
          execute("ALTER TABLE #{table} DROP COLUMN #{name}")
        end

        def add_index(table, columns, options = {})
          columns = Array(columns)
          index_name = options[:name] || "#{table}_#{columns.join('_')}_index"
          unique = options[:unique] ? "UNIQUE " : ""
          execute("CREATE #{unique}INDEX #{index_name} ON #{table} (#{columns.join(', ')})")
        end

        def remove_index(table, columns)
          columns = Array(columns)
          index_name = options[:name] || "#{table}_#{columns.join('_')}_index"
          execute("DROP INDEX #{index_name} ON #{table}")
        end

        def execute(sql)
          connection.query(sql)
        end

        def table_exists?(name)
          result = connection.query("SHOW TABLES LIKE '#{name}'")
          result.count > 0
        end

        def column_exists?(table, column)
          result = connection.query("SHOW COLUMNS FROM #{table} LIKE '#{column}'")
          result.count > 0
        end

        private

        def type_to_sql(type)
          case type.to_s
          when 'string' then 'VARCHAR(255)'
          when 'text' then 'TEXT'
          when 'integer' then 'INT'
          when 'bigint' then 'BIGINT'
          when 'float' then 'FLOAT'
          when 'decimal' then 'DECIMAL(10,2)'
          when 'boolean' then 'TINYINT(1)'
          when 'date' then 'DATE'
          when 'datetime', 'timestamp' then 'DATETIME'
          when 'json' then 'JSON'
          else type.to_s.upcase
          end
        end

        def quote(value)
          case value
          when nil then 'NULL'
          when true then '1'
          when false then '0'
          when Numeric then value.to_s
          else "'#{connection.escape(value.to_s)}'"
          end
        end
      end

      class SQLiteAdapter < Base
        def create_table(name, &block)
          builder = TableBuilder.new(name, self)
          builder.instance_eval(&block)
          execute(builder.to_sql)
        end

        def drop_table(name)
          execute("DROP TABLE IF EXISTS #{name}")
        end

        def add_column(table, name, type, options = {})
          sql = "ALTER TABLE #{table} ADD COLUMN #{name} #{type_to_sql(type)}"
          sql += " NOT NULL" if options[:null] == false
          sql += " DEFAULT #{quote(options[:default])}" if options.key?(:default)
          execute(sql)
        end

        def remove_column(table, name)
          # SQLite doesn't support DROP COLUMN in older versions
          # This is a simplified version
          execute("ALTER TABLE #{table} DROP COLUMN #{name}")
        end

        def add_index(table, columns, options = {})
          columns = Array(columns)
          index_name = options[:name] || "#{table}_#{columns.join('_')}_index"
          unique = options[:unique] ? "UNIQUE " : ""
          execute("CREATE #{unique}INDEX IF NOT EXISTS #{index_name} ON #{table} (#{columns.join(', ')})")
        end

        def remove_index(table, columns)
          columns = Array(columns)
          index_name = "#{table}_#{columns.join('_')}_index"
          execute("DROP INDEX IF EXISTS #{index_name}")
        end

        def execute(sql)
          connection.execute(sql)
        end

        def table_exists?(name)
          result = connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            [name.to_s]
          )
          result.any?
        end

        def column_exists?(table, column)
          result = connection.execute("PRAGMA table_info(#{table})")
          result.any? { |row| row['name'] == column.to_s }
        end

        private

        def type_to_sql(type)
          case type.to_s
          when 'string', 'text' then 'TEXT'
          when 'integer', 'bigint' then 'INTEGER'
          when 'float', 'decimal' then 'REAL'
          when 'boolean' then 'INTEGER'
          when 'date', 'datetime', 'timestamp' then 'TEXT'
          when 'json' then 'TEXT'
          else type.to_s.upcase
          end
        end

        def quote(value)
          case value
          when nil then 'NULL'
          when true then '1'
          when false then '0'
          when Numeric then value.to_s
          else "'#{value}'"
          end
        end
      end

      class TableBuilder
        attr_reader :table_name, :adapter, :columns, :indexes

        def initialize(table_name, adapter)
          @table_name = table_name
          @adapter = adapter
          @columns = []
          @indexes = []
        end

        def column(name, type, options = {})
          @columns << { name: name, type: type, options: options }
        end

        def primary_key(name = :id)
          column(name, :primary_key)
        end

        def string(name, options = {})
          column(name, :string, options)
        end

        def text(name, options = {})
          column(name, :text, options)
        end

        def integer(name, options = {})
          column(name, :integer, options)
        end

        def bigint(name, options = {})
          column(name, :bigint, options)
        end

        def float(name, options = {})
          column(name, :float, options)
        end

        def decimal(name, options = {})
          column(name, :decimal, options)
        end

        def boolean(name, options = {})
          column(name, :boolean, options)
        end

        def date(name, options = {})
          column(name, :date, options)
        end

        def datetime(name, options = {})
          column(name, :datetime, options)
        end

        def timestamp(name, options = {})
          column(name, :timestamp, options)
        end

        def json(name, options = {})
          column(name, :json, options)
        end

        def uuid(name, options = {})
          column(name, :uuid, options)
        end

        def timestamps
          datetime(:created_at, null: false)
          datetime(:updated_at, null: false)
        end

        def index(columns, options = {})
          @indexes << { columns: columns, options: options }
        end

        def to_sql
          columns_sql = @columns.map do |col|
            sql = "#{col[:name]} #{type_to_sql(col[:type])}"
            sql += " PRIMARY KEY" if col[:type] == :primary_key
            sql += " NOT NULL" if col[:options][:null] == false
            sql += " DEFAULT #{quote(col[:options][:default])}" if col[:options].key?(:default)
            sql
          end

          sql = "CREATE TABLE IF NOT EXISTS #{@table_name} (#{columns_sql.join(', ')})"
          sql
        end

        private

        def type_to_sql(type)
          @adapter.send(:type_to_sql, type)
        end

        def quote(value)
          @adapter.send(:quote, value)
        end
      end
    end
  end
end
