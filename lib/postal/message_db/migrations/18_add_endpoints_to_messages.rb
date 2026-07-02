# frozen_string_literal: true

module Postal
  module MessageDB
    module Migrations
      class AddEndpointsToMessages < Postal::MessageDB::Migration

        def up
          @database.provisioner.add_column(:messages, :endpoint_id, "int(11)")
          @database.provisioner.add_column(:messages, :endpoint_type, "varchar(255)")
        end

      end
    end
  end
end
