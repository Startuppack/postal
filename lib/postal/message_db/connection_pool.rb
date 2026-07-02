# frozen_string_literal: true

module Postal
  module MessageDB
    class ConnectionPool

      attr_reader :connections

      def initialize
        @connections = []
        @lock = Mutex.new
      end

      def use
        retried = false
        do_not_checkin = false
        begin
          connection = checkout

          yield connection
        rescue => e
          if connection && connection_lost?(connection, e)
            do_not_checkin = true
            if retried == false
              retried = true
              retry
            end
          end
          raise
        ensure
          checkin(connection) unless do_not_checkin
        end
      end

      private

      def connection_lost?(connection, error)
        case connection.adapter
        when :mysql2
          error.is_a?(Mysql2::Error) &&
            error.message =~ /(lost connection|gone away|not connected)/i
        when :postgresql
          defined?(PG::Error) && error.is_a?(PG::Error) &&
            error.message =~ /(server closed the connection|connection not open)/i
        else
          false
        end
      end

      def checkout
        @lock.synchronize do
          return @connections.pop unless @connections.empty?
        end

        add_new_connection
        checkout
      end

      def checkin(connection)
        @lock.synchronize do
          @connections << connection
        end
      end

      def add_new_connection
        @lock.synchronize do
          @connections << establish_connection
        end
      end

      def establish_connection
        Connection.build(
          host:     Postal::Config.message_db.host,
          username: Postal::Config.message_db.username,
          password: Postal::Config.message_db.password,
          port:     Postal::Config.message_db.port,
          encoding: Postal::Config.message_db.encoding,
          database: Postal::Config.message_db.respond_to?(:database) ? Postal::Config.message_db.database : "postal_messages"
        )
      end

    end
  end
end
