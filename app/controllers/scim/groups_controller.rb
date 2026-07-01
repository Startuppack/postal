# frozen_string_literal: true

# SCIM Groups for a tenant = the org itself.
# No create/destroy — orgs are managed via the admin API v2.
# PATCH supports both member operations and org attribute updates.
module Scim
  class GroupsController < BaseController

    # GET /scim/v2/tenants/:org/Groups — returns the single group (the org)
    def index
      render json: scim_list([scim_group(@organization)], 1), content_type: CONTENT_TYPE
    end

    # GET /scim/v2/tenants/:org/Groups/:id
    def show
      unless params[:id] == @organization.id.to_s || params[:id] == @organization.permalink
        return render json: scim_error("Group not found", 404), status: :not_found,
                      content_type: CONTENT_TYPE
      end
      render json: scim_group(@organization), content_type: CONTENT_TYPE
    end

    # PUT/PATCH /scim/v2/tenants/:org/Groups/:id
    # Handles:
    #   - Org attribute updates (displayName, urn:postal:1.0:org extension)
    #   - Member add/remove via SCIM Operations
    #   - Full member replace on PUT (members array)
    def update
      unless params[:id] == @organization.id.to_s || params[:id] == @organization.permalink
        return render json: scim_error("Group not found", 404), status: :not_found,
                      content_type: CONTENT_TYPE
      end

      # Org attribute updates
      org_attrs = {}
      org_attrs[:name] = body_params["displayName"] if body_params["displayName"].present?

      postal_ext = body_params["urn:postal:1.0:org"] || {}
      org_attrs[:time_zone] = postal_ext["time_zone"] if postal_ext["time_zone"].present?
      org_attrs[:permalink] = postal_ext["permalink"] if postal_ext["permalink"].present?

      @organization.update!(org_attrs) if org_attrs.any?

      # Member operations (SCIM PATCH Operations)
      operations = body_params["Operations"] || []
      operations.each do |op|
        case op["op"]&.downcase
        when "add"
          members = Array(op["value"])
          sync_members(members)
        when "remove"
          Array(op["value"]).each { |m| remove_member(m["value"]) }
        when "replace"
          if op["path"].nil?
            # Full replace
            @organization.name = op["value"]["displayName"] if op.dig("value", "displayName").present?
            @organization.save! if @organization.changed?
            sync_members(op["value"]["members"]) if op["value"]["members"].is_a?(Array)
          elsif op["path"] == "members"
            sync_members(Array(op["value"]))
          end
        end
      end

      # Full member replace on PUT (members key at root, no Operations)
      if operations.empty? && body_params["members"].is_a?(Array)
        sync_members(body_params["members"])
      end

      render json: scim_group(@organization.reload), content_type: CONTENT_TYPE
    end

    private

    def sync_members(members)
      return unless members.is_a?(Array)

      members.each do |m|
        user = User.find_by(id: m["value"]) || User.find_by(email_address: m["value"])
        next unless user

        ou = @organization.organization_users.find_by(user: user, user_type: "User")
        role = m["role"].to_s.presence
        role = "member" unless OrganizationUser::ROLES.include?(role)

        if ou
          ou.update!(role: role, admin: role == "admin", all_servers: role != "readonly")
        else
          @organization.organization_users.create!(
            user: user, user_type: "User",
            role: role, admin: role == "admin", all_servers: role != "readonly"
          )
        end
      end
    end

    def remove_member(user_ref)
      user = User.find_by(id: user_ref) || User.find_by(email_address: user_ref)
      return unless user

      @organization.organization_users.where(user: user, user_type: "User").destroy_all
    end

    def scim_group(org)
      members = org.organization_users.where(user_type: "User").includes(:user).map do |ou|
        { value: ou.user_id.to_s, display: ou.user&.name, role: ou.role }
      end
      {
        schemas:     ["urn:ietf:params:scim:schemas:core:2.0:Group"],
        id:          org.id.to_s,
        displayName: org.name,
        externalId:  org.permalink,
        members:     members,
        "urn:postal:1.0:org": {
          permalink:  org.permalink,
          time_zone:  org.time_zone,
          status:     org.status
        },
        meta: {
          resourceType: "Group",
          location:     "#{base_url}/Groups/#{org.id}"
        }
      }
    end

  end
end
