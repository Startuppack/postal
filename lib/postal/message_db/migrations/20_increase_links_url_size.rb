# frozen_string_literal: true

module Postal
  module MessageDB
    module Migrations
      class IncreaseLinksUrlSize < Postal::MessageDB::Migration

        def up
          @database.provisioner.modify_column(:links, :url, "TEXT")
        end

      end
    end
  end
end
