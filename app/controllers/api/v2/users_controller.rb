# frozen_string_literal: true

module Api
  module V2
    class UsersController < BaseController

      before_action :set_user, only: [:show, :update, :destroy]

      def index
        users = paginate(User.order(:email_address))
        render json: users.map { |u| serialize(u) }
      end

      def show
        render json: serialize(@user)
      end

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

      def destroy
        @user.destroy!
        head :no_content
      end

      private

      def set_user
        @user = User.find_by(uuid: params[:id]) ||
                User.find_by!(email_address: params[:id])
      end

      def user_params
        params.permit(:first_name, :last_name, :email_address, :time_zone, :admin)
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
            {
              permalink: o.permalink,
              name:      o.name
            }
          }
        }
      end

    end
  end
end
