# frozen_string_literal: true

module Api
  module V2
    class ServersController < BaseController

      before_action :set_organization
      before_action :set_server, only: [:show, :update, :destroy, :suspend, :unsuspend]

      def index
        servers = paginate(@organization.servers.present.order(:name))
        render json: servers.map { |s| serialize(s) }
      end

      def show
        render json: serialize(@server)
      end

      def create
        server = @organization.servers.new(server_params)
        server.save!
        render json: serialize(server), status: :created
      end

      def update
        @server.update!(server_params)
        render json: serialize(@server)
      end

      def destroy
        @server.soft_destroy
        head :no_content
      end

      def suspend
        @server.update!(suspended_at: Time.now, suspension_reason: params[:reason])
        render json: serialize(@server)
      end

      def unsuspend
        @server.update!(suspended_at: nil, suspension_reason: nil)
        render json: serialize(@server)
      end

      private

      def set_organization
        @organization = Organization.present.find_by!(permalink: params[:organization_id])
      end

      def set_server
        @server = @organization.servers.present.find_by!(permalink: params[:id])
      end

      def server_params
        params.permit(:name, :permalink, :mode, :send_limit,
                      :spam_threshold, :spam_failure_threshold,
                      :postmaster_address, :privacy_mode, :log_smtp_data,
                      :raw_message_retention_days, :raw_message_retention_size,
                      :message_retention_days)
      end

      def serialize(server)
        {
          id:                          server.uuid,
          permalink:                   server.permalink,
          name:                        server.name,
          mode:                        server.mode,
          status:                      server.status,
          send_limit:                  server.send_limit,
          spam_threshold:              server.spam_threshold,
          spam_failure_threshold:      server.spam_failure_threshold,
          postmaster_address:          server.postmaster_address,
          privacy_mode:                server.privacy_mode,
          raw_message_retention_days:  server.raw_message_retention_days,
          raw_message_retention_size:  server.raw_message_retention_size,
          message_retention_days:      server.message_retention_days,
          suspended_at:                server.suspended_at,
          suspension_reason:           server.suspension_reason,
          token:                       server.token,
          organization_permalink:      @organization.permalink,
          created_at:                  server.created_at,
          updated_at:                  server.updated_at
        }
      end

    end
  end
end
