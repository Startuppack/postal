# frozen_string_literal: true

module Scim
  class BaseController < ApplicationController
    skip_before_action :login_required
    skip_before_action :verify_authenticity_token
    before_action :authenticate_scim!

    CONTENT_TYPE = "application/scim+json"

    private

    def authenticate_scim!
      header = request.headers["Authorization"]
      token = header&.delete_prefix("Bearer ")
      unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, Postal::Config.scim.bearer_token.to_s)
        render json: scim_error("Unauthorized", 401), status: :unauthorized
      end
    end

    def scim_error(detail, status = 400)
      {
        schemas: ["urn:ietf:params:scim:api:messages:2.0:Error"],
        status: status.to_s,
        detail: detail
      }
    end

    def scim_list(resources, total)
      {
        schemas: ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
        totalResults: total,
        startIndex: 1,
        itemsPerPage: resources.size,
        Resources: resources
      }
    end
  end
end
