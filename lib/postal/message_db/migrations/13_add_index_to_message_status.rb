# frozen_string_literal: true

module Postal
  module MessageDB
    module Migrations
      class AddIndexToMessageStatus < Postal::MessageDB::Migration

        def up
          @database.provisioner.add_index(:messages, :on_status, "`status`(8)")
        end

      end
    end
  end
end
