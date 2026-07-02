# frozen_string_literal: true

module Postal
  module MessageDB
    class Provisioner

      # MySQL column-type patterns → PostgreSQL equivalents.
      # Applied left-to-right; first match wins.
      PG_TYPE_MAP = [
        [/\bint\(\d+\)\s+NOT NULL\s+AUTO_INCREMENT\b/i,  "serial NOT NULL"],
        [/\bint\(\d+\)\s+DEFAULT\s+(\S+)/i,              'integer DEFAULT \1'],
        [/\bint\(\d+\)/i,                                 "integer"],
        [/\btinyint\(1\)\s+DEFAULT\s+0\b/i,              "boolean DEFAULT false"],
        [/\btinyint\(1\)\s+DEFAULT\s+NULL\b/i,           "boolean DEFAULT NULL"],
        [/\btinyint\(1\)/i,                               "boolean"],
        [/\blongblob\b/i,                                 "bytea"],
        [/\bmediumblob\b/i,                               "bytea"],
        [/\bmediumtext\b/i,                               "text"],
        [/\bdecimal\((\d+),(\d+)\)/i,                    'numeric(\1,\2)'],
        [/\bDEFAULT\s+0\b/,                              "DEFAULT 0"],
      ].freeze

      def initialize(database)
        @database = database
      end

      # Provision a fresh database/schema, dropping any prior one.
      def provision
        drop
        create
        migrate(silent: true)
      end

      def migrate(start_from: @database.schema_version, silent: false)
        Postal::MessageDB::Migration.run(@database, start_from: start_from, silent: silent)
      end

      def exists?
        if postgresql?
          !!@database.query(
            "SELECT schema_name FROM information_schema.schemata " \
            "WHERE schema_name = '#{@database.database_name}'"
          ).first
        else
          !!@database.query(
            "SELECT schema_name FROM `information_schema`.`schemata` " \
            "WHERE schema_name = '#{@database.database_name}'"
          ).first
        end
      end

      def create
        if postgresql?
          @database.query("CREATE SCHEMA #{qi(@database.database_name)}")
        else
          @database.query(
            "CREATE DATABASE #{qi(@database.database_name)} " \
            "CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci;"
          )
        end
        true
      rescue => e
        raise unless db_error?(e) && e.message =~ /already exists/i
        false
      end

      def drop
        if postgresql?
          @database.query("DROP SCHEMA IF EXISTS #{qi(@database.database_name)} CASCADE")
        else
          @database.query("DROP DATABASE IF EXISTS #{qi(@database.database_name)}")
        end
        true
      rescue => e
        raise unless db_error?(e) && e.message =~ /doesn't exist|does not exist/i
        false
      end

      def create_table(table_name, options)
        if postgresql?
          @database.query(create_table_query_pg(table_name, options))
        else
          @database.query(create_table_query_mysql(table_name, options))
        end
      end

      def drop_table(table_name)
        @database.query("DROP TABLE #{qt(table_name)}")
      end

      def clean
        %w[clicks deliveries links live_stats loads messages
           raw_message_sizes spam_checks stats_daily stats_hourly
           stats_monthly stats_yearly suppressions webhook_requests].each do |table|
          @database.query("TRUNCATE #{qt(table)}")
        end
      end

      def create_raw_table(table)
        create_table(table, columns: {
          id:   "int(11) NOT NULL AUTO_INCREMENT",
          data: "longblob DEFAULT NULL",
          next: "int(11) DEFAULT NULL"
        })
        @database.query(
          "INSERT INTO #{qt(:raw_message_sizes)} (table_name, size) " \
          "VALUES ('#{table}', 0)"
        )
      rescue => e
        raise unless db_error?(e) && e.message =~ /already exists/i
      end

      def raw_tables(max_age = 30)
        earliest_date = max_age ? Time.now.utc.to_date - max_age : nil
        [].tap do |tables|
          list_tables("raw-%").each do |tbl_name|
            date = Date.parse(tbl_name.gsub(/\Araw-/, ""))
            tables << tbl_name if earliest_date.nil? || date < earliest_date
          end
        end.sort
      end

      def remove_raw_tables_older_than(max_age = 30)
        raw_tables(max_age).each { |t| remove_raw_table(t) }
      end

      def remove_raw_table(table)
        @database.query(
          "UPDATE #{qt(:messages)} " \
          "SET raw_table = NULL, raw_headers_id = NULL, raw_body_id = NULL, size = NULL " \
          "WHERE raw_table = '#{table}'"
        )
        @database.query(
          "DELETE FROM #{qt(:raw_message_sizes)} WHERE table_name = '#{table}'"
        )
        drop_table(table)
      end

      def remove_messages(max_age = 60)
        time = (Time.now.utc.to_date - max_age.days).to_time.end_of_day
        return unless (newest = @database.select(:messages,
                                                 where: { timestamp: { less_than_or_equal_to: time.to_f } },
                                                 limit: 1, order: :id, direction: "DESC",
                                                 fields: [:id]).first)

        id = newest["id"]
        %w[clicks loads deliveries spam_checks].each do |tbl|
          @database.query("DELETE FROM #{qt(tbl)} WHERE message_id <= #{id}")
        end
        @database.query("DELETE FROM #{qt(:messages)} WHERE id <= #{id}")
      end

      def remove_raw_tables_until_less_than_size(size)
        tables = raw_tables(nil)
        tables_removed = []
        until @database.total_size <= size
          table = tables.shift
          tables_removed << table
          remove_raw_table(table)
        end
        tables_removed
      end

      private

      # List tables in the current namespace matching a SQL LIKE pattern.
      def list_tables(pattern)
        if postgresql?
          @database.query(
            "SELECT tablename FROM pg_tables " \
            "WHERE schemaname = '#{@database.database_name}' " \
            "AND tablename LIKE '#{pattern}'"
          ).map { |row| row["tablename"] }
        else
          @database.query(
            "SHOW TABLES FROM #{qi(@database.database_name)} LIKE '#{pattern}'"
          ).map { |row| row.to_a.first.last }
        end
      end

      # Shorthand: qualified table reference for the current namespace.
      def qt(table)
        "#{qi(@database.database_name)}.#{qi(table)}"
      end

      # Quote a single identifier.
      def qi(name)
        if postgresql?
          "\"#{name.to_s.gsub('"', '""')}\""
        else
          "`#{name.to_s.gsub('`', '``')}`"
        end
      end

      def db_error?(e)
        e.is_a?(Mysql2::Error) || (defined?(PG::Error) && e.is_a?(PG::Error))
      end

      def with_conn(&block)
        Database.connection_pool.use(&block)
      end

      def postgresql?
        Postal::Config.message_db.respond_to?(:adapter) &&
          Postal::Config.message_db.adapter.to_s == "postgresql"
      end

      # Translate a MySQL column-type string to its PostgreSQL equivalent.
      def pg_type(mysql_type)
        PG_TYPE_MAP.reduce(mysql_type) do |t, (pattern, replacement)|
          t.gsub(pattern, replacement)
        end
      end

      # Quote identifier for index names (no schema prefix needed).
      def qi_plain(name)
        with_conn { |c| c.quote_identifier(name) }
      end

      # Build CREATE TABLE (+ CREATE INDEX) SQL for PostgreSQL.
      def create_table_query_pg(table_name, options)
        # primary_key may be pre-backtick-quoted MySQL syntax (single or composite).
        # Convert each backtick-quoted identifier to PG double-quote, drop prefix lengths.
        pk_raw = options[:primary_key] ? options[:primary_key].to_s : "`id`"
        pk = pk_raw.gsub(/`([^`]*)`(?:\(\d+\))?/) { qi($1) }
        pk = qi(pk_raw) unless pk.include?('"')
        cols = options[:columns].map do |col_name, col_type|
          "#{qi(col_name)} #{pg_type(col_type)}"
        end
        cols << "PRIMARY KEY (#{pk})"

        stmts = ["CREATE TABLE #{qt(table_name)} (#{cols.join(', ')})"]

        (options[:indexes] || {}).each do |idx_name, idx_cols|
          # Strip MySQL prefix-length hints (col(8)) and backtick quoting
          clean_cols = idx_cols.gsub(/\(\d+\)/, "").gsub("`", "").split(",").map(&:strip)
          quoted     = clean_cols.map { |c| qi(c) }.join(", ")
          stmts << "CREATE INDEX #{qi_plain(idx_name)} ON #{qt(table_name)} (#{quoted})"
        end

        (options[:unique_indexes] || {}).each do |idx_name, idx_cols|
          clean_cols = idx_cols.gsub(/\(\d+\)/, "").gsub("`", "").split(",").map(&:strip)
          quoted     = clean_cols.map { |c| qi(c) }.join(", ")
          stmts << "CREATE UNIQUE INDEX #{qi_plain(idx_name)} ON #{qt(table_name)} (#{quoted})"
        end

        stmts.join("; ")
      end

      # Build CREATE TABLE SQL for MySQL (original logic preserved).
      def create_table_query_mysql(table_name, options)
        String.new.tap do |s|
          s << "CREATE TABLE #{qt(table_name)} ("
          s << options[:columns].map do |col_name, col_opts|
            "`#{col_name}` #{col_opts}"
          end.join(", ")
          if options[:indexes]
            s << ", "
            s << options[:indexes].map do |idx_name, idx_opts|
              "KEY `#{idx_name}` (#{idx_opts}) USING BTREE"
            end.join(", ")
          end
          if options[:unique_indexes]
            s << ", "
            s << options[:unique_indexes].map do |idx_name, idx_opts|
              "UNIQUE KEY `#{idx_name}` (#{idx_opts})"
            end.join(", ")
          end
          # primary_key is already backtick-quoted MySQL syntax (single or composite).
          pk = options[:primary_key] ? options[:primary_key].to_s : "`id`"
          s << ", PRIMARY KEY (#{pk})"
          s << ") ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4;"
        end
      end

    end
  end
end
