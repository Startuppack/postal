# frozen_string_literal: true

module Scim
  class UsersController < BaseController

    def index
      org_users = @organization.organization_users.where(user_type: "User").includes(:user)
      users = org_users.map(&:user).compact
      render json: scim_list(users.map { |u| scim_user(u) }, users.size), content_type: CONTENT_TYPE
    end

    def show
      user = find_org_user!(params[:id])
      return if performed?

      render json: scim_user(user), content_type: CONTENT_TYPE
    end

    def create
      email      = body_params.dig("emails", 0, "value") || body_params["userName"]
      name_obj   = body_params["name"] || {}
      first_name = name_obj["givenName"]  || body_params["displayName"]&.split(" ")&.first || email
      last_name  = name_obj["familyName"] || body_params["displayName"]&.split(" ")&.last  || ""
      role       = body_params["role"].to_s.presence
      role       = "member" unless OrganizationUser::ROLES.include?(role)

      user = User.find_by(email_address: email)
      if user.nil?
        user = User.new(email_address: email, first_name: first_name, last_name: last_name)
        user.password = SecureRandom.hex(24)
        unless user.save
          return render json: scim_error(user.errors.full_messages.join(", ")), status: :unprocessable_entity,
                        content_type: CONTENT_TYPE
        end
      end

      ou = @organization.organization_users.find_by(user: user, user_type: "User")
      unless ou
        @organization.organization_users.create!(
          user: user, user_type: "User",
          role: role, admin: role == "admin", all_servers: role != "readonly"
        )
      end

      render json: scim_user(user), status: :created, content_type: CONTENT_TYPE
    end

    def update
      user = find_org_user!(params[:id])
      return if performed?

      attrs = {}
      if (name_obj = body_params["name"])
        attrs[:first_name] = name_obj["givenName"]  if name_obj["givenName"]
        attrs[:last_name]  = name_obj["familyName"] if name_obj["familyName"]
      end
      user.update(attrs) if attrs.any?

      # Role change via SCIM PATCH Operations or top-level role field
      new_role = extract_role_from_body
      if new_role
        ou = @organization.organization_users.find_by(user: user, user_type: "User")
        ou&.update!(role: new_role, admin: new_role == "admin", all_servers: new_role != "readonly")
      end

      render json: scim_user(user), content_type: CONTENT_TYPE
    end

    def destroy
      user = find_org_user!(params[:id])
      return if performed?

      @organization.organization_users.where(user: user, user_type: "User").destroy_all
      user.destroy if user.organization_users.reload.empty?
      head :no_content
    end

    private

    def find_org_user!(identifier)
      user = User.find_by(id: identifier) || User.find_by(email_address: identifier)
      unless user && @organization.organization_users.where(user: user, user_type: "User").exists?
        render json: scim_error("User not found in tenant", 404), status: :not_found,
               content_type: CONTENT_TYPE
        return nil
      end
      user
    end

    def extract_role_from_body
      role = body_params["role"].to_s.presence
      return role if OrganizationUser::ROLES.include?(role)

      # SCIM PATCH Operations: { "op": "replace", "path": "role", "value": "admin" }
      ops = body_params["Operations"] || []
      ops.each do |op|
        next unless op["op"]&.downcase == "replace" && op["path"] == "role"

        r = op["value"].to_s
        return r if OrganizationUser::ROLES.include?(r)
      end
      nil
    end

    def scim_user(user)
      ou = @organization.organization_users.find_by(user: user, user_type: "User")
      {
        schemas:  ["urn:ietf:params:scim:schemas:core:2.0:User"],
        id:       user.id.to_s,
        userName: user.email_address,
        name: {
          givenName:  user.first_name,
          familyName: user.last_name,
          formatted:  user.name
        },
        emails:   [{ value: user.email_address, primary: true }],
        role:     ou&.role || "member",
        active:   true,
        meta: {
          resourceType: "User",
          location:     "#{base_url}/Users/#{user.id}"
        }
      }
    end

  end
end
