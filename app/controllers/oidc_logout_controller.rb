# frozen_string_literal: true

# Handles OIDC logout flows initiated by the identity provider.
#
# Back-Channel Logout (BCL) spec: https://openid.net/specs/openid-connect-backchannel-1_0.html
# When the IdP (e.g. Keycloak) logs a user out, it POSTs a signed logout_token here.
# We validate the token and invalidate all active Authie sessions for that user.
class OidcLogoutController < ApplicationController

  skip_before_action :login_required
  skip_before_action :verify_authenticity_token

  # POST /auth/oidc/backchannel_logout
  def backchannel
    return head :not_found unless Postal::Config.oidc.enabled?

    raw = params[:logout_token]
    return render plain: "Missing logout_token", status: :bad_request unless raw.present?

    begin
      payload = Postal::OIDCProviders.decode_jwt(raw)
    rescue JWT::DecodeError => e
      Postal.logger.warn("BCL: invalid logout_token — #{e.message}")
      return render plain: "Invalid logout_token: #{e.message}", status: :bad_request
    end

    # BCL spec: must contain the backchannel-logout event
    events = payload["events"] || {}
    unless events.key?("http://schemas.openid.net/event/backchannel-logout")
      return render plain: "Not a BCL logout_token (missing events claim)", status: :bad_request
    end

    # BCL spec: must NOT contain nonce
    if payload.key?("nonce")
      return render plain: "logout_token must not contain nonce", status: :bad_request
    end

    sub = payload["sub"].to_s
    return render plain: "Missing sub claim", status: :bad_request if sub.blank?

    user = User.find_by(oidc_uid: sub) ||
           User.find_by(email_address: payload["email"].to_s)

    if user
      sessions = Authie::Session.where(user_id: user.id, active: true)
      count    = sessions.count
      sessions.each { |s| s.invalidate! rescue nil }
      Postal.logger.info("BCL: invalidated #{count} session(s) for #{user.email_address} (sub=#{sub})")
    else
      Postal.logger.warn("BCL: no user found for sub=#{sub}")
    end

    head :ok
  end

end
