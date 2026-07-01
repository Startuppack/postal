# frozen_string_literal: true

# == Schema Information
#
# Table name: organization_users
#
#  id              :integer          not null, primary key
#  organization_id :integer
#  user_id         :integer
#  created_at      :datetime
#  admin           :boolean          default(FALSE)
#  all_servers     :boolean          default(TRUE)
#  user_type       :string(255)
#

class OrganizationUser < ApplicationRecord

  ROLES = %w[admin member readonly].freeze

  belongs_to :organization
  belongs_to :user, polymorphic: true, optional: true

  validates :role, inclusion: { in: ROLES }, allow_nil: true

  def admin?
    role == "admin"
  end

  def readonly?
    role == "readonly"
  end

  def member?
    role == "member"
  end

end
