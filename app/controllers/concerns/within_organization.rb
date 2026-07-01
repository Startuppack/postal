# frozen_string_literal: true

module WithinOrganization

  extend ActiveSupport::Concern

  included do
    helper_method :organization, :current_organization_user,
                  :organization_admin?, :organization_readonly?
    before_action :add_organization_to_page_title
  end

  private

  def organization
    @organization ||= current_user.organizations_scope.find_by_permalink!(params[:org_permalink])
  end

  def current_organization_user
    @current_organization_user ||=
      organization.organization_users.find_by(user: current_user, user_type: "User")
  end

  def organization_admin?
    current_organization_user&.admin?
  end

  def organization_readonly?
    current_organization_user&.readonly?
  end

  # Call this in before_action to block readonly users from write operations.
  def require_write_access!
    return unless organization_readonly?

    respond_to do |format|
      format.html { redirect_to organization_root_path(org_permalink: organization.permalink), alert: "You have read-only access to this organization." }
      format.json { render json: { error: "Read-only access" }, status: :forbidden }
    end
  end

  # Call this in before_action to restrict org settings to admins.
  def require_org_admin!
    return if organization_admin?

    respond_to do |format|
      format.html { redirect_to organization_root_path(org_permalink: organization.permalink), alert: "Administrator access required." }
      format.json { render json: { error: "Admin access required" }, status: :forbidden }
    end
  end

  def add_organization_to_page_title
    page_title << organization.name
  end

end
