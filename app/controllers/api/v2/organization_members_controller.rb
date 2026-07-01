# frozen_string_literal: true

module Api
  module V2
    class OrganizationMembersController < BaseController

      before_action :set_organization
      before_action :set_member, only: [:update, :destroy]

      def index
        members = @organization.organization_users.where(user_type: "User").includes(:user)
        render json: members.map { |ou| serialize(ou) }
      end

      # POST /api/v2/organizations/:org/members
      # Body: { user_id: "<uuid or email>", role: "admin|member|readonly" }
      def create
        user = find_user!(params[:user_id])
        return if performed?

        ou = @organization.organization_users.find_by(user: user, user_type: "User")
        if ou
          render json: serialize(ou), status: :ok
          return
        end

        role = valid_role(params.fetch(:role, "member"))
        ou = @organization.organization_users.create!(
          user: user,
          user_type: "User",
          role: role,
          admin: role == "admin",
          all_servers: role != "readonly"
        )
        render json: serialize(ou), status: :created
      end

      # PATCH /api/v2/organizations/:org/members/:id
      # Body: { role: "admin|member|readonly" }
      def update
        role = valid_role(params[:role])
        @member.update!(
          role: role,
          admin: role == "admin",
          all_servers: role != "readonly"
        )
        render json: serialize(@member)
      end

      def destroy
        @member.destroy!
        head :no_content
      end

      private

      def set_organization
        @organization = Organization.present.find_by!(permalink: params[:organization_id])
      end

      def set_member
        user = find_user!(params[:id])
        return if performed?
        @member = @organization.organization_users.find_by!(user: user, user_type: "User")
      end

      def find_user!(identifier)
        user = User.find_by(uuid: identifier) || User.find_by(email_address: identifier)
        render json: { error: "User not found: #{identifier}" }, status: :not_found unless user
        user
      end

      def valid_role(role)
        role = role.to_s.presence || "member"
        unless OrganizationUser::ROLES.include?(role)
          render json: { errors: ["role must be one of: #{OrganizationUser::ROLES.join(', ')}"] },
                 status: :unprocessable_entity
          return "member"
        end
        role
      end

      def serialize(ou)
        user = ou.user
        {
          user_id:     user&.uuid,
          email:       user&.email_address,
          first_name:  user&.first_name,
          last_name:   user&.last_name,
          role:        ou.role || (ou.admin? ? "admin" : "member"),
          admin:       ou.admin,
          all_servers: ou.all_servers,
          joined_at:   ou.created_at
        }
      end

    end
  end
end
