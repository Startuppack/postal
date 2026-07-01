# frozen_string_literal: true

module Api
  module V2
    class OauthController < ActionController::Base

      skip_before_action :verify_authenticity_token

      rescue_from StandardError do |e|
        render json: { error: "server_error", error_description: e.message }, status: :internal_server_error
      end

      def token
        case params[:grant_type]
        when "client_credentials" then handle_client_credentials
        when "password"           then handle_password
        else
          render json: { error: "unsupported_grant_type" }, status: :bad_request
        end
      end

      private

      def handle_client_credentials
        cid  = params[:client_id].to_s
        csec = params[:client_secret].to_s

        config_id  = Postal::Config.api.client_id.to_s
        config_sec = Postal::Config.api.client_secret.to_s

        unless cid == config_id &&
               config_sec.present? &&
               ActiveSupport::SecurityUtils.secure_compare(csec, config_sec)
          return render json: { error: "invalid_client" }, status: :unauthorized
        end

        payload = base_payload.merge("sub" => cid, "scope" => "admin")
        render_token(payload)
      end

      def handle_password
        email    = params[:username].to_s
        password = params[:password].to_s

        begin
          user = User.authenticate(email, password)
        rescue Postal::Errors::AuthenticationError
          return render json: { error: "invalid_grant", error_description: "Invalid credentials" }, status: :unauthorized
        end

        payload = base_payload.merge(
          "sub"     => user.email_address,
          "user_id" => user.id,
          "scope"   => user.admin? ? "admin" : "user"
        )
        render_token(payload)
      end

      def base_payload
        now = Time.now.to_i
        ttl = Postal::Config.api.token_ttl
        { "iat" => now, "nbf" => now, "exp" => now + ttl, "iss" => "postal" }
      end

      def render_token(payload)
        token = JWT.encode(payload, Postal::Config.api.jwt_secret.to_s, "HS256")
        render json: {
          access_token: token,
          token_type:   "Bearer",
          expires_in:   Postal::Config.api.token_ttl,
          scope:        payload["scope"]
        }
      end

    end
  end
end
