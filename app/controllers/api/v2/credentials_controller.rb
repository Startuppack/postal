# frozen_string_literal: true

module Api
  module V2
    class CredentialsController < BaseController

      before_action :set_organization
      before_action :set_server
      before_action :set_credential, only: [:show, :destroy]
      before_action(only: [:create, :destroy]) { require_org_write!(@organization) }

      def index
        render json: paginate(@server.credentials.order(:name)).map { |c| serialize(c) }
      end

      def show
        render json: serialize(@credential)
      end

      def create
        credential = @server.credentials.new(credential_params)
        credential.save!
        render json: serialize(credential), status: :created
      end

      def destroy
        @credential.destroy!
        head :no_content
      end

      private

      def set_organization
        @organization = organizations_scope.find_by!(permalink: params[:organization_id])
      end

      def set_server
        @server = @organization.servers.present.find_by!(permalink: params[:server_id])
      end

      def set_credential
        @credential = @server.credentials.find_by!(uuid: params[:id])
      end

      def credential_params
        params.permit(:name, :type)
      end

      def serialize(cred)
        {
          id:           cred.uuid,
          name:         cred.name,
          type:         cred.type,
          key:          cred.key,
          hold:         cred.hold,
          last_used_at: cred.last_used_at,
          created_at:   cred.created_at,
          updated_at:   cred.updated_at
        }
      end

    end
  end
end
