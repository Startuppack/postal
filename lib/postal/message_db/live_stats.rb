# frozen_string_literal: true

module Postal
  module MessageDB
    class LiveStats

      def initialize(database)
        @database = database
      end

      #
      # Increment the live stats by one for the current minute
      #
      def increment(type)
        time     = Time.now.utc
        type_val = @database.escape(type.to_s)
        table    = @database.qualify_table(:live_stats)

        if @database.postgresql?
          sql_query  = "INSERT INTO #{table} (type, minute, timestamp, count)"
          sql_query += " VALUES (#{type_val}, #{time.min}, #{time.to_f}, 1)"
          sql_query += " ON CONFLICT (minute, type) DO UPDATE SET"
          sql_query += "   count = CASE WHEN live_stats.timestamp < #{time.to_f - 1800} THEN 1"
          sql_query += "                ELSE live_stats.count + 1 END,"
          sql_query += "   timestamp = #{time.to_f}"
        else
          sql_query  = "INSERT INTO #{table} (type, minute, timestamp, count)"
          sql_query += " VALUES (#{type_val}, #{time.min}, #{time.to_f}, 1)"
          sql_query += " ON DUPLICATE KEY UPDATE count = if(timestamp < #{time.to_f - 1800}, 1, count + 1),"
          sql_query += " timestamp = #{time.to_f}"
        end
        @database.query(sql_query)
      end

      #
      # Return the total number of messages for the last 60 minutes
      #
      def total(minutes, options = {})
        if minutes > 60
          raise Postal::Error, "Live stats can only return data for the last 60 minutes."
        end

        options[:types] ||= [:incoming, :outgoing]
        raise Postal::Error, "You must provide at least one type to return" if options[:types].empty?

        time     = minutes.minutes.ago.beginning_of_minute.utc.to_f
        types    = options[:types].map { |t| @database.escape(t.to_s) }.join(", ")
        table    = @database.qualify_table(:live_stats)
        type_col = @database.escape_identifier(:type)
        result   = @database.query("SELECT SUM(count) as count FROM #{table} WHERE #{type_col} IN (#{types}) AND timestamp > #{time}").first
        result["count"] || 0
      end

    end
  end
end
