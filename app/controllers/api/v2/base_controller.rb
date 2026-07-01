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
        raw = request.headers["Authorization"]&.delete_prefix("Bearer ")&.strip
        return render_unauthorized("Missing token") unless raw.present?

        begin
          payload, = JWT.decode(raw, Postal::Config.api.jwt_secret.to_s, true, { algorithms: ["HS256"] })
          @current_token_payload = payload
        rescue JWT::ExpiredSignature
          render_unauthorized("Token expired")
        rescue JWT::DecodeError => e
          render_unauthorized(e.message)
        end
      end

      def current_token_payload
        @current_token_payload
      end

      def token_scope
        current_token_payload&.fetch("scope", nil)
      end

      def admin_token?
        token_scope == "admin"
      end

      def token_user
        return @token_user if defined?(@token_user)

        user_id = current_token_payload&.fetch("user_id", nil)
        @token_user = user_id ? User.find_by(id: user_id) : nil
      end

      def render_unauthorized(message = "Unauthorized")
        render json: { error: "unauthorized", error_description: message }, status: :unauthorized
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
