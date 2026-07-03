# frozen_string_literal: true

require "net/http"
require "json"

module Postal
  # Central registry for OIDC providers.
  #
  # Supports two configuration modes:
  #   1. Multi-provider: set `oidc.providers` array in postal.yml
  #   2. Single-provider (legacy): use the flat `oidc.*` fields
  #
  # Usage:
  #   Postal::OIDCProviders.all                        # => [{id: "keycloak", ...}, ...]
  #   Postal::OIDCProviders.find_by_id("keycloak")
  #   Postal::OIDCProviders.find_by_issuer("https://...")
  #   Postal::OIDCProviders.decode_jwt(raw_token)      # raises JWT::DecodeError
  #   Postal::OIDCProviders.end_session_endpoint_for(provider)
  module OIDCProviders

    def self.all
      @all ||= load_providers
    end

    def self.reset!
      @all = nil
    end

    def self.find_by_id(id)
      all.find { |p| p[:id] == id.to_s }
    end

    def self.find_by_issuer(iss)
      norm = iss.to_s.chomp("/")
      all.find { |p| p[:issuer].to_s.chomp("/") == norm }
    end

    def self.any?
      all.any?
    end

    # Decode and verify a JWT against any registered provider's JWKS.
    # Returns the payload hash. Raises JWT::DecodeError if no provider validates.
    def self.decode_jwt(token)
      last_error = nil
      all.each do |provider|
        begin
          payload, = JWT.decode(token, nil, true, {
            algorithms: ["RS256"],
            jwks:       ->(opts) { fetch_jwks_for(provider, kid_not_found: opts[:kid_not_found]) },
            iss:        provider[:issuer],
            verify_iss: true
          })
          return payload
        rescue JWT::InvalidIssuerError, JWT::DecodeError => e
          last_error = e
        end
      end
      raise last_error || JWT::DecodeError.new("No configured OIDC provider could validate this token")
    end

    def self.end_session_endpoint_for(provider)
      discovery_for(provider)["end_session_endpoint"]
    rescue => e
      Rails.logger.error("OIDC: end_session_endpoint lookup failed for #{provider[:id]}: #{e.message}")
      nil
    end

    def self.fetch_jwks_for(provider, kid_not_found: false)
      cache_key = "postal_oidc_jwks_#{provider[:id]}"
      Rails.cache.delete(cache_key) if kid_not_found
      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        JSON.parse(Net::HTTP.get(URI(jwks_uri_for(provider))))
      end
    end

    def self.jwks_uri_for(provider)
      provider[:jwks_uri].presence || discovery_for(provider)["jwks_uri"]
    end

    def self.discovery_for(provider)
      cache_key = "postal_oidc_discovery_#{provider[:id]}"
      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        issuer = provider[:issuer].to_s.chomp("/")
        JSON.parse(Net::HTTP.get(URI("#{issuer}/.well-known/openid-configuration")))
      end
    rescue => e
      Rails.logger.error("OIDC: discovery failed for #{provider[:id]}: #{e.message}")
      {}
    end

    private

    def self.load_providers
      raw            = load_raw_config
      providers_yaml = raw.dig("oidc", "providers")

      if providers_yaml.is_a?(Array) && providers_yaml.any?
        providers_yaml.each_with_index.map { |p, i| normalize_provider(p, i) }
      elsif Postal::Config.oidc.enabled? && Postal::Config.oidc.issuer.to_s.present?
        [provider_from_flat_config]
      else
        []
      end
    end

    def self.normalize_provider(p, index)
      {
        id:                      (p["id"].presence || "provider_#{index}").gsub(/[^a-z0-9_]/, "_"),
        display_name:            p["display_name"].presence || "Login with OIDC",
        issuer:                  p["issuer"].to_s,
        identifier:              p["identifier"].to_s,
        secret:                  p["secret"].to_s,
        scopes:                  (Array(p["scopes"]).map(&:to_s).presence || ["openid", "email"]),
        uid_field:               (p["uid_field"].presence || "preferred_username").to_s,
        email_address_field:     (p["email_address_field"].presence || "email").to_s,
        name_field:              (p["name_field"].presence || "name").to_s,
        pkce:                    p.fetch("pkce", false),
        discovery:               p.fetch("discovery", true),
        jwks_uri:                p["jwks_uri"].to_s.presence,
        authorization_endpoint:  p["authorization_endpoint"].to_s.presence,
        token_endpoint:          p["token_endpoint"].to_s.presence,
        userinfo_endpoint:       p["userinfo_endpoint"].to_s.presence
      }
    end

    def self.provider_from_flat_config
      c = Postal::Config.oidc
      {
        id:                     "oidc",
        display_name:           c.name.to_s.presence || "OIDC Provider",
        issuer:                 c.issuer.to_s,
        identifier:             c.identifier.to_s,
        secret:                 c.secret.to_s,
        scopes:                 c.scopes.map(&:to_s),
        uid_field:              c.uid_field.to_s,
        email_address_field:    c.email_address_field.to_s,
        name_field:             c.name_field.to_s,
        pkce:                   c.pkce?,
        discovery:              c.discovery?,
        jwks_uri:               c.jwks_uri.to_s.presence,
        authorization_endpoint: c.authorization_endpoint.to_s.presence,
        token_endpoint:         c.token_endpoint.to_s.presence,
        userinfo_endpoint:      c.userinfo_endpoint.to_s.presence
      }
    end

    def self.load_raw_config
      YAML.load_file(Postal.config_file_path)
    rescue => e
      Rails.logger.warn("OIDCProviders: could not read raw config: #{e.message}")
      {}
    end

  end
end
