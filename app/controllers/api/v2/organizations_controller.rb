# frozen_string_literal: true

module API
  module V2
    class OrganizationsController < BaseController

      before_action :set_organization, only: [:show, :update, :destroy, :suspend, :unsuspend]
      before_action(only: [:create, :destroy, :suspend, :unsuspend]) { require_superadmin! }
      before_action(only: [:update]) { require_org_admin!(@organization) }

      def index
        render json: paginate(organizations_scope.order(:name)).map { |o| serialize(o) }
      end

      def show
        render json: serialize(@organization)
      end

      def create
        owner = User.find_by!(email_address: params[:owner_email])

        # A soft-deleted residual keeps its (unique) permalink, so a plain create
        # would fail with "permalink has already been taken". We must NOT restore
        # such a residual: a slug can be reclaimed by a *different* customer, and
        # restoring would resurrect the previous tenant's servers, message data
        # and credentials — a cross-tenant data leak. Instead, hard-purge any
        # residual (org#destroy cascades server#destroy, whose after_commit drops
        # the per-server message-DB schema) so the new org starts from a clean,
        # empty slate.
        Organization.deleted.where(permalink: org_params[:permalink]).find_each do |residual|
          residual.servers.find_each(&:destroy)
          residual.destroy
        end

        org = Organization.new(org_params)
        org.owner = owner
        org.save!
        org.organization_users.create!(user: owner, user_type: "User",
                                       role: "admin", admin: true, all_servers: true)

        unless params[:skip_default_server]
          server = org.servers.new(name: org.name, mode: "Live")
          server.save!
          server.credentials.create!(name: "Default SMTP", type: "SMTP")
        end

        render json: serialize(org), status: :created
      end

      def update
        @organization.update!(org_params)
        render json: serialize(@organization)
      end

      def destroy
        if purge_requested?
          # Hard purge: `destroy` cascades servers (each Server's after_commit on
          # :destroy drops its message-DB schema), domains, members, credentials,
          # endpoints and routes — nothing is left behind. Use for a full tenant
          # teardown; the default soft-delete keeps the org recoverable.
          @organization.destroy
        else
          @organization.soft_destroy
        end
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
        # A purge must be able to reach an already soft-deleted residual, so widen
        # the scope to include deleted orgs for that case only.
        scope = if action_name == "destroy" && purge_requested?
                  api_admin? ? Organization.all : current_api_user.organizations
                else
                  organizations_scope
                end
        @organization = scope.find_by!(permalink: params[:id])
      end

      def purge_requested?
        ActiveModel::Type::Boolean.new.cast(params[:purge])
      end

      def org_params
        params.permit(:name, :permalink, :time_zone)
      end

      def serialize(org)
        {
          id:                org.uuid,
          permalink:         org.permalink,
          name:              org.name,
          time_zone:         org.time_zone,
          status:            org.status,
          owner_email:       org.owner&.email_address,
          suspended_at:      org.suspended_at,
          suspension_reason: org.suspension_reason,
          created_at:        org.created_at,
          updated_at:        org.updated_at
        }
      end

    end
  end
end
