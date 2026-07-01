# frozen_string_literal: true

module Scim
  class BaseController < ApplicationController
    skip_before_action :login_required
    skip_before_action :verify_authenticity_token
    before_action :authenticate_scim!
    before_action :set_organization

    CONTENT_TYPE = "application/scim+json"

    private

    def authenticate_scim!
      token = request.headers["Authorization"]&.delete_prefix("Bearer ")&.strip
      unless token.present? &&
             ActiveSupport::SecurityUtils.secure_compare(token, Postal::Config.scim.bearer_token.to_s)
        render json: scim_error("Unauthorized", 401), status: :unauthorized
      end
    end

    def set_organization
      @organization = Organization.present.find_by(permalink: params[:org_permalink])
      unless @organization
        render json: scim_error("Tenant '#{params[:org_permalink]}' not found", 404), status: :not_found
      end
    end

    def body_params
      @body_params ||= begin
        raw = request.body.read
        raw.present? ? JSON.parse(raw) : {}
      rescue JSON::ParserError
        {}
      end
    end

    def scim_error(detail, status = 400)
      {
        schemas: ["urn:ietf:params:scim:api:messages:2.0:Error"],
        status:  status.to_s,
        detail:  detail
      }
    end

    def scim_list(resources, total)
      {
        schemas:      ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
        totalResults: total,
        startIndex:   1,
        itemsPerPage: resources.size,
        Resources:    resources
      }
    end

    def base_url
      "#{request.base_url}/scim/v2/tenants/#{@organization.permalink}"
    end
  end
end
