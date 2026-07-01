# frozen_string_literal: true

require "net/http"
require "json"

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

        issuer = Postal::Config.oidc.issuer.to_s
        if issuer.blank?
          return render json: { error: "server_error", error_description: "OIDC issuer not configured" },
                        status: :internal_server_error
        end

        begin
          payload, = JWT.decode(raw, nil, true, {
            algorithms:  ["RS256"],
            jwks:        ->(opts) { fetch_jwks(opts) },
            iss:         issuer,
            verify_iss:  true
          })
          @current_token_payload = payload
        rescue JWT::ExpiredSignature
          return render_unauthorized("Token expired")
        rescue JWT::DecodeError => e
          return render_unauthorized(e.message)
        end

        required_azp = Postal::Config.api.required_azp.to_s
        if required_azp.present? && @current_token_payload["azp"].to_s != required_azp
          return render json: { error: "forbidden", error_description: "azp mismatch" }, status: :forbidden
        end
      end

      def current_token_payload
        @current_token_payload
      end

      # Fetch JWKS from Keycloak, auto-discovered via OIDC discovery or jwks_uri config.
      # Caches for 1 hour; busts cache on unknown kid (key rotation).
      def fetch_jwks(opts = {})
        Rails.cache.delete("postal_api_v2_jwks") if opts[:kid_not_found]
        Rails.cache.fetch("postal_api_v2_jwks", expires_in: 1.hour) do
          JSON.parse(Net::HTTP.get(URI(resolve_jwks_uri)))
        end
      end

      def resolve_jwks_uri
        # 1. Explicit config
        explicit = Postal::Config.oidc.jwks_uri.to_s
        return explicit if explicit.present?

        # 2. OIDC discovery (default for Keycloak)
        issuer = Postal::Config.oidc.issuer.to_s.chomp("/")
        discovery = Rails.cache.fetch("postal_oidc_discovery", expires_in: 1.hour) do
          JSON.parse(Net::HTTP.get(URI("#{issuer}/.well-known/openid-configuration")))
        end
        discovery["jwks_uri"]
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
