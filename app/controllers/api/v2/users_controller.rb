# frozen_string_literal: true

module API
  module V2
    class UsersController < BaseController

      before_action :set_user, only: [:show, :update, :destroy]
      before_action(only: [:destroy]) { require_superadmin! }

      # Super admin → all users.
      # Org admin   → users who are members of their orgs.
      def index
        render json: paginate(accessible_users.order(:email_address)).map { |u| serialize(u) }
      end

      def show
        render json: serialize(@user)
      end

      # Both super admin and org admin can create users.
      def create
        user = User.new(user_params)
        user.password = params[:password] if params[:password].present?
        user.save!
        render json: serialize(user), status: :created
      end

      def update
        @user.update!(user_params)
        render json: serialize(@user)
      end

      # Delete a Postal user globally — super admin only.
      def destroy
        @user.destroy!
        head :no_content
      end

      private

      # Scope: super admin sees everyone; org admin sees their orgs' members only.
      def accessible_users
        return User.all if api_admin?

        admin_org_ids = current_api_user
                          .organization_users
                          .where(user_type: "User", admin: true)
                          .pluck(:organization_id)

        User.joins(:organization_users)
            .where(organization_users: { organization_id: admin_org_ids, user_type: "User" })
            .distinct
      end

      def set_user
        scope = accessible_users
        @user = scope.find_by(uuid: params[:id]) || scope.find_by(email_address: params[:id])
        render_not_found unless @user
      end

      def user_params
        allowed = [:first_name, :last_name, :email_address, :time_zone]
        allowed << :admin if api_admin?
        params.permit(allowed)
      end

      def serialize(user)
        {
          id:            user.uuid,
          first_name:    user.first_name,
          last_name:     user.last_name,
          email_address: user.email_address,
          admin:         user.admin,
          time_zone:     user.time_zone,
          created_at:    user.created_at,
          updated_at:    user.updated_at,
          organizations: user.organizations.present.map { |o|
            { permalink: o.permalink, name: o.name }
          }
        }
      end

    end
  end
end
