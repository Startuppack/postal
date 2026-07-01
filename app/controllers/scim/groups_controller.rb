# frozen_string_literal: true

module Scim
  class GroupsController < BaseController
    def index
      orgs = Organization.order(:id)
      render json: scim_list(orgs.map { |o| scim_group(o) }, orgs.count), content_type: CONTENT_TYPE
    end

    def show
      org = Organization.find_by(id: params[:id])
      return render json: scim_error("Group not found", 404), status: :not_found unless org

      render json: scim_group(org), content_type: CONTENT_TYPE
    end

    def create
      slug = body_params["externalId"] || body_params["displayName"]&.parameterize || SecureRandom.hex(6)
      name = body_params["displayName"] || slug
      owner_id = body_params.dig("members", 0, "value")

      org = Organization.find_or_initialize_by(permalink: slug)
      if org.new_record?
        org.name = name
        owner = owner_id ? User.find_by(id: owner_id) : nil
        owner ||= User.first
        org.owner = owner
        org.save!
        if owner
          org.organization_users.create!(user: owner, user_type: "User",
                                         role: "admin", admin: true, all_servers: true)
        end
        # Auto-create a default SMTP server for the org
        server = org.servers.new(name: org.name, mode: "Live")
        server.save!
        server.credentials.create!(name: "Default SMTP", type: "SMTP")
      end

      sync_members(org, body_params["members"])
      render json: scim_group(org), status: :created, content_type: CONTENT_TYPE
    end

    def update
      org = Organization.find_by(id: params[:id])
      return render json: scim_error("Group not found", 404), status: :not_found unless org

      operations = body_params["Operations"] || []
      operations.each do |op|
        case op["op"]&.downcase
        when "add"
          members = op["value"].is_a?(Array) ? op["value"] : [op["value"]]
          sync_members(org, members)
        when "remove"
          members = op["value"].is_a?(Array) ? op["value"] : [op["value"]]
          members.each do |m|
            user = User.find_by(id: m["value"])
            if user
              org.organization_users.where(user: user, user_type: "User").destroy_all
              user.destroy if user.organization_users.reload.empty?
            end
          end
          if org.organization_users.reload.empty?
            org.destroy
            return head :no_content
          end
        when "replace"
          sync_members(org, op["value"]) if op["path"].nil?
        end
      end

      render json: scim_group(org), content_type: CONTENT_TYPE
    end

    def destroy
      org = Organization.find_by(id: params[:id])
      return render json: scim_error("Group not found", 404), status: :not_found unless org

      cleanup_orphaned_users(org)
      org.destroy
      head :no_content
    end

    private

    def body_params
      @body_params ||= begin
        raw = request.body.read
        raw.present? ? JSON.parse(raw) : {}
      end
    end

    def cleanup_orphaned_users(org)
      org.organization_users.where(user_type: "User").includes(:user).each do |ou|
        user = ou.user
        next unless user
        other_orgs = user.organization_users.where.not(organization_id: org.id)
        user.destroy if other_orgs.empty?
      end
    end

    def sync_members(org, members)
      return unless members.is_a?(Array)

      members.each do |m|
        user = User.find_by(id: m["value"])
        next unless user
        next if org.organization_users.where(user: user, user_type: "User").exists?

        role = m["role"].to_s.presence
        role = "member" unless OrganizationUser::ROLES.include?(role)
        org.organization_users.create!(
          user: user,
          user_type: "User",
          role: role,
          admin: role == "admin",
          all_servers: role != "readonly"
        )
      end
    end

    def scim_group(org)
      members = org.organization_users.where(user_type: "User").includes(:user).map do |ou|
        { value: ou.user_id.to_s, display: ou.user&.name }
      end
      {
        schemas: ["urn:ietf:params:scim:schemas:core:2.0:Group"],
        id: org.id.to_s,
        displayName: org.name,
        externalId: org.permalink,
        members: members,
        meta: {
          resourceType: "Group",
          location: scim_group_url(org)
        }
      }
    end
  end
end
