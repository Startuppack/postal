# frozen_string_literal: true

module API
  module V2
    class DomainsController < BaseController

      before_action :set_organization
      before_action :set_server, only: [:index, :show, :create, :destroy, :verify, :dns_check]
      before_action :set_domain, only: [:show, :destroy, :verify, :dns_check]
      before_action(only: [:create, :destroy, :verify]) { require_org_write!(@organization) }

      def index
        scope = @server ? @server.domains : @organization.domains
        render json: paginate(scope.order(:name)).map { |d| serialize(d) }
      end

      def show
        render json: serialize(@domain)
      end

      def create
        owner = @server || @organization
        domain = owner.domains.new(domain_params)
        domain.save!
        render json: serialize(domain), status: :created
      end

      def destroy
        @domain.destroy!
        head :no_content
      end

      # Force-marks the domain as verified without DNS check — super admin or org write.
      def verify
        @domain.update_columns(verified_at: Time.now) unless @domain.verified?
        render json: serialize(@domain)
      end

      def dns_check
        @domain.check_dns
        render json: serialize(@domain)
      end

      private

      def set_organization
        @organization = organizations_scope.find_by!(permalink: params[:organization_id])
      end

      def set_server
        return unless params[:server_id]

        @server = @organization.servers.present.find_by!(permalink: params[:server_id])
      end

      def set_domain
        scope = @server ? @server.domains : @organization.domains
        @domain = scope.find_by!(uuid: params[:id])
      end

      def domain_params
        params.permit(:name, :verification_method, :outgoing, :incoming, :use_for_any)
      end

      def serialize(domain)
        {
          id:                      domain.uuid,
          name:                    domain.name,
          verified:                domain.verified?,
          verified_at:             domain.verified_at,
          outgoing:                domain.outgoing,
          incoming:                domain.incoming,
          verification_method:     domain.verification_method,
          dns_verification_string: domain.dns_verification_string,
          dkim_record_name:        domain.dkim_record_name,
          dkim_record:             domain.dkim_record,
          spf_status:              domain.spf_status,
          spf_error:               domain.spf_error,
          dkim_status:             domain.dkim_status,
          dkim_error:              domain.dkim_error,
          mx_status:               domain.mx_status,
          mx_error:                domain.mx_error,
          return_path_status:      domain.return_path_status,
          return_path_error:       domain.return_path_error,
          dns_checked_at:          domain.dns_checked_at,
          created_at:              domain.created_at,
          updated_at:              domain.updated_at
        }
      end

    end
  end
end
