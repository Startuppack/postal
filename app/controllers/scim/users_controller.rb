# frozen_string_literal: true

module Scim
  class UsersController < BaseController
    def index
      users = User.order(:id)
      render json: scim_list(users.map { |u| scim_user(u) }, users.count), content_type: CONTENT_TYPE
    end

    def show
      user = User.find_by(id: params[:id])
      return render json: scim_error("User not found", 404), status: :not_found unless user

      render json: scim_user(user), content_type: CONTENT_TYPE
    end

    def create
      email = body_params.dig("emails", 0, "value") || body_params["userName"]
      name_obj = body_params["name"] || {}
      first_name = name_obj["givenName"] || body_params["displayName"]&.split(" ")&.first || email
      last_name = name_obj["familyName"] || body_params["displayName"]&.split(" ")&.last || ""

      user = User.find_by(email_address: email)
      if user.nil?
        user = User.new(
          email_address: email,
          first_name: first_name,
          last_name: last_name
        )
        user.password = SecureRandom.hex(24)
        unless user.save
          return render json: scim_error(user.errors.full_messages.join(", ")), status: :unprocessable_entity
        end
      end

      assign_to_groups(user, body_params["groups"])
      render json: scim_user(user), status: :created, content_type: CONTENT_TYPE
    end

    def update
      user = User.find_by(id: params[:id])
      return render json: scim_error("User not found", 404), status: :not_found unless user

      attrs = {}
      if (name_obj = body_params["name"])
        attrs[:first_name] = name_obj["givenName"] if name_obj["givenName"]
        attrs[:last_name] = name_obj["familyName"] if name_obj["familyName"]
      end
      user.update(attrs) if attrs.any?
      render json: scim_user(user), content_type: CONTENT_TYPE
    end

    def destroy
      user = User.find_by(id: params[:id])
      return render json: scim_error("User not found", 404), status: :not_found unless user

      user.destroy
      head :no_content
    end

    private

    def body_params
      @body_params ||= begin
        raw = request.body.read
        raw.present? ? JSON.parse(raw) : {}
      end
    end

    def assign_to_groups(user, groups)
      return unless groups.is_a?(Array)

      groups.each do |g|
        org = Organization.find_by(id: g["value"])
        next unless org
        next if org.organization_users.where(user: user, user_type: "User").exists?

        org.organization_users.create!(user: user, user_type: "User", admin: true, all_servers: true)
      end
    end

    def scim_user(user)
      {
        schemas: ["urn:ietf:params:scim:schemas:core:2.0:User"],
        id: user.id.to_s,
        userName: user.email_address,
        name: {
          givenName: user.first_name,
          familyName: user.last_name,
          formatted: user.name
        },
        emails: [{ value: user.email_address, primary: true }],
        active: true,
        meta: {
          resourceType: "User",
          location: scim_v2_user_url(user)
        }
      }
    end
  end
end
