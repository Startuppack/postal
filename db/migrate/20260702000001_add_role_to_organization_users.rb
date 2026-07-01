# frozen_string_literal: true

class AddRoleToOrganizationUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :organization_users, :role, :string, default: "member", null: false

    # Backfill: existing admins become "admin", everyone else stays "member"
    reversible do |dir|
      dir.up do
        execute "UPDATE organization_users SET role = 'admin' WHERE admin = 1"
      end
    end
  end
end
