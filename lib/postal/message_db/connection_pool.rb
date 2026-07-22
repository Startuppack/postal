# frozen_string_literal: true

module Postal
  module MessageDB
    class ConnectionPool

      attr_reader :connections

      def initialize
        @connections = []
        @lock = Mutex.new
      end

      # Maximum number of times a single #use call will discard a dead pooled
      # connection and retry with a fresh one. A restart of the message database
      # (postgres-global) leaves EVERY pooled connection dead, so a single retry
      # is not enough — each retry only clears one dead connection off the pool.
      MAX_RECONNECT_ATTEMPTS = 3

      def use
        attempts = 0
        loop do
          connection = checkout
          begin
            result = yield connection
          rescue => e
            # A lost connection failed BEFORE reaching the server (e.g. the socket
            # was already closed), so the block had no side effect and retrying is
            # safe. Discard the dead connection (do NOT return it to the pool) and
            # take a fresh one. Without this, the dead connection is checked back
            # in and every subsequent query fails forever until the process is
            # restarted (observed as "PQsocket() can't get socket descriptor").
            if connection_lost?(connection, e) && (attempts += 1) <= MAX_RECONNECT_ATTEMPTS
              begin
                connection.close
              rescue StandardError
                nil
              end
              next
            end
            checkin(connection)
            raise
          end
          checkin(connection)
          return result
        end
      end

      private

      def connection_lost?(connection, error)
        case connection.adapter
        when :mysql2
          error.is_a?(Mysql2::Error) &&
            error.message =~ /(lost connection|gone away|not connected)/i
        when :postgresql
          return false unless defined?(PG::Error) && error.is_a?(PG::Error)
          # Connection-level failures are their own error classes in the pg gem
          # (PG::ConnectionBad covers "server closed the connection unexpectedly",
          # "PQsocket() can't get socket descriptor", "no connection to the
          # server"; PG::UnableToSend covers a broken write). Match those by class
          # first, then fall back to a broadened message match for anything the
          # gem raises as a generic PG::Error on a dead socket.
          (defined?(PG::ConnectionBad) && error.is_a?(PG::ConnectionBad)) ||
            (defined?(PG::UnableToSend) && error.is_a?(PG::UnableToSend)) ||
            error.message =~ /(server closed the connection|connection not open|no connection to the server|PQsocket|not connected|terminating connection|connection reset|broken pipe|EOF detected)/i
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
