# frozen_string_literal: true

module Postal
  module MessageDB
    module Migrations
      class AddReplacedLinkCountToMessages < Postal::MessageDB::Migration

        def up
          @database.provisioner.add_column(:messages, :tracked_links, "int(11) DEFAULT 0")
          @database.provisioner.add_column(:messages, :tracked_images, "int(11) DEFAULT 0")
          # tinyint without (1) → MySQL integer (0/1), PG smallint
          @database.provisioner.add_column(:messages, :parsed, "tinyint DEFAULT 0")
        end

      end
    end
  end
end
