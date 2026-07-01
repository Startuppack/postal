# frozen_string_literal: true

module Api
  module V2
    class OrganizationsController < BaseController

      before_action :set_organization, only: [:show, :update, :destroy, :suspend, :unsuspend]

      def index
        orgs = paginate(Organization.present.order(:name))
        render json: orgs.map { |o| serialize(o) }
      end

      def show
        render json: serialize(@organization)
      end

      def create
        owner = User.find_by!(email_address: params[:owner_email])
        org = Organization.new(org_params)
        org.owner = owner
        org.save!
        org.organization_users.create!(user: owner, admin: true, all_servers: true)
        render json: serialize(org), status: :created
      end

      def update
        @organization.update!(org_params)
        render json: serialize(@organization)
      end

      def destroy
        @organization.soft_destroy
        head :no_content
      end

      def suspend
        @organization.update!(suspended_at: Time.now, suspension_reason: params[:reason])
        render json: serialize(@organization)
      end

      def unsuspend
        @organization.update!(suspended_at: nil, suspension_reason: nil)
        render json: serialize(@organization)
      end

      private

      def set_organization
        @organization = Organization.present.find_by!(permalink: params[:id])
      end

      def org_params
        params.permit(:name, :permalink, :time_zone)
      end

      def serialize(org)
        {
          id:               org.uuid,
          permalink:        org.permalink,
          name:             org.name,
          time_zone:        org.time_zone,
          status:           org.status,
          owner_email:      org.owner&.email_address,
          suspended_at:     org.suspended_at,
          suspension_reason: org.suspension_reason,
          created_at:       org.created_at,
          updated_at:       org.updated_at
        }
      end

    end
  end
end
