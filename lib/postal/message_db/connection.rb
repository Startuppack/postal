# frozen_string_literal: true

module Postal
  module MessageDB
    # Unified connection wrapper providing a common API over both MySQL2 and PostgreSQL.
    #
    # MySQL model : one database per mail-server (database_name = "postal-server-N")
    # PostgreSQL  : one schema  per mail-server within a single PostgreSQL database
    #               (schema name also "postal-server-N", quoted with double-quotes)
    class Connection

      attr_reader :adapter, :last_id, :affected_rows

      def self.build(config)
        case Postal::Config.message_db.adapter.to_s
        when "postgresql" then new_postgresql(config)
        else                   new_mysql(config)
        end
      end

      def self.new_mysql(config)
        new(:mysql2, Mysql2::Client.new(
          host:     config[:host],
          username: config[:username],
          password: config[:password],
          port:     config[:port],
          encoding: config[:encoding]
        ))
      end

      def self.new_postgresql(config)
        require "pg"
        conn = PG.connect(
          host:     config[:host],
          port:     config[:port],
          user:     config[:username],
          password: config[:password],
          dbname:   config[:database]
        )
        type_map = PG::BasicTypeMapForResults.new(conn)
        new(:postgresql, conn, type_map: type_map)
      end

      def initialize(adapter, raw_conn, type_map: nil)
        @adapter      = adapter
        @raw_conn     = raw_conn
        @type_map     = type_map
        @last_id      = nil
        @affected_rows = 0
      end

      # Execute any SQL and return an array of hashes.
      # cast_booleans is accepted for API compat but ignored for PG (handled by type_map).
      def query(sql, cast_booleans: false)
        case @adapter
        when :mysql2
          result = @raw_conn.query(sql, cast_booleans: cast_booleans)
          @affected_rows = @raw_conn.affected_rows
          @last_id       = @raw_conn.last_id
          result.to_a
        when :postgresql
          result = @raw_conn.exec(sql)
          result.map_types!(@type_map) if @type_map
          @affected_rows = result.cmd_tuples
          @last_id = nil
          result.to_a
        end
      end

      # Execute an INSERT statement and return the generated primary-key value.
      # For PostgreSQL, appends RETURNING id to the statement.
      # Falls back to plain INSERT (last_id = nil) when the table has no "id" column.
      def insert(sql)
        case @adapter
        when :mysql2
          @raw_conn.query(sql)
          @affected_rows = @raw_conn.affected_rows
          @last_id       = @raw_conn.last_id
        when :postgresql
          begin
            result = @raw_conn.exec("#{sql} RETURNING id")
            result.map_types!(@type_map) if @type_map
            @affected_rows = result.cmd_tuples
            @last_id = result.ntuples > 0 ? result.getvalue(0, 0).to_i : nil
          rescue PG::UndefinedColumn
            result = @raw_conn.exec(sql)
            @affected_rows = result.cmd_tuples
            @last_id = nil
          end
        end
        @last_id
      end

      # Escape a string value for safe interpolation into SQL.
      def escape_string(str)
        case @adapter
        when :mysql2      then @raw_conn.escape(str)
        when :postgresql  then @raw_conn.escape_string(str)
        end
      end

      # Quote a database identifier (table name, column name, schema/database name).
      def quote_identifier(name)
        case @adapter
        when :mysql2      then "`#{name.to_s.gsub('`', '``')}`"
        when :postgresql  then "\"#{name.to_s.gsub('"', '""')}\""
        end
      end

      # Generate a qualified "namespace.table" reference.
      # namespace = database name (MySQL) or schema name (PostgreSQL).
      def qualify(namespace, table)
        "#{quote_identifier(namespace)}.#{quote_identifier(table)}"
      end

      # Error class for this adapter.
      def error_class
        case @adapter
        when :mysql2     then Mysql2::Error
        when :postgresql then (defined?(PG::Error) ? PG::Error : StandardError)
        end
      end

      # Pattern that matches "object does not exist" errors from this adapter.
      def not_found_pattern
        case @adapter
        when :mysql2     then /(doesn't exist|database exists|already exists)/i
        when :postgresql then /(does not exist|already exists)/i
        end
      end

      def close
        @raw_conn.close
      end

      def postgresql?
        @adapter == :postgresql
      end

      def mysql2?
        @adapter == :mysql2
      end

    end
  end
end
