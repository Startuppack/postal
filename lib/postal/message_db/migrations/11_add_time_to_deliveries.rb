# frozen_string_literal: true

module Postal
  module MessageDB
    module Migrations
      class AddTimeToDeliveries < Postal::MessageDB::Migration

        def up
          @database.provisioner.add_column(:deliveries, :time, "decimal(8,2)")
        end

      end
    end
  end
end
