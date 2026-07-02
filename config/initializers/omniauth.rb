# frozen_string_literal: true

if Postal::Config.oidc.enabled?
  Postal::OidcProviders.reset!
  providers = Postal::OidcProviders.all
  base_url  = "#{Postal::Config.postal.web_protocol}://#{Postal::Config.postal.web_hostname}"

  if providers.any?
    Rails.application.config.middleware.use OmniAuth::Builder do
      providers.each do |prov|
        client_options = {
          identifier:   prov[:identifier],
          secret:       prov[:secret],
          redirect_uri: "#{base_url}/auth/#{prov[:id]}/callback"
        }

        unless prov[:discovery]
          client_options[:authorization_endpoint] = prov[:authorization_endpoint]
          client_options[:token_endpoint]         = prov[:token_endpoint]
          client_options[:userinfo_endpoint]      = prov[:userinfo_endpoint]
          client_options[:jwks_uri]               = prov[:jwks_uri]
        end

        provider :openid_connect,
                 name:           prov[:id].to_sym,
                 scope:          prov[:scopes].map(&:to_sym),
                 uid_field:      prov[:uid_field],
                 issuer:         prov[:issuer],
                 pkce:           prov[:pkce],
                 discovery:      prov[:discovery],
                 client_options: client_options
      end
    end

    OmniAuth.config.on_failure = proc do |env|
      SessionsController.action(:oauth_failure).call(env)
    end
  end
end
