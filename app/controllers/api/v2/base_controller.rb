# frozen_string_literal: true

module Api
  module V2
    class BaseController < ActionController::Base

      skip_before_action :verify_authenticity_token
      before_action :authenticate!

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActiveRecord::RecordInvalid do |e|
        render_error :unprocessable_entity, e.record.errors.full_messages
      end

      private

      def authenticate!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")&.strip
        unless token.present? &&
               ActiveSupport::SecurityUtils.secure_compare(token, Postal::Config.api.bearer_token.to_s)
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end

      def render_not_found
        render json: { error: "Not found" }, status: :not_found
      end

      def render_error(status, messages)
        render json: { errors: Array(messages) }, status: status
      end

      def paginate(scope)
        page  = [params[:page].to_i, 1].max
        limit = [[params[:per_page].to_i, 1].max, 200].min
        limit = 50 if limit.zero?
        scope.offset((page - 1) * limit).limit(limit)
      end

    end
  end
end
