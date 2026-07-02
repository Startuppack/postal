# frozen_string_literal: true

module Postal
  module MessageDB
    module Migrations
      class AddUrlAndHookToWebhooks < Postal::MessageDB::Migration

        def up
          @database.provisioner.add_column(:webhook_requests, :url, "varchar(255)")
          @database.provisioner.add_column(:webhook_requests, :webhook_id, "int(11)")
          @database.provisioner.add_index(:webhook_requests, :on_webhook_id, "`webhook_id`")
        end

      end
    end
  end
end
