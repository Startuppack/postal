# frozen_string_literal: true

module Postal
  module MessageDB
    module Migrations
      class AddHoldExpiry < Postal::MessageDB::Migration

        def up
          @database.provisioner.add_column(:messages, :hold_expiry, "decimal(18,6)")
        end

      end
    end
  end
end
