# frozen_string_literal: true

class SessionsController < ApplicationController

  layout "sub"

  before_action :require_local_authentication, only: [:create, :begin_password_reset, :finish_password_reset]
  skip_before_action :login_required, only: [:new, :create, :begin_password_reset, :finish_password_reset, :ip, :raise_error, :create_from_oidc, :oauth_failure]

  def create
    login(User.authenticate(params[:email_address], params[:password]))
    flash[:remember_login] = true
    redirect_to_with_return_to root_path
  rescue Postal::Errors::AuthenticationError
    flash.now[:alert] = "The credentials you've provided are incorrect. Please check and try again."
    render "new"
  end

  def destroy
    auth_session.invalidate! if logged_in?
    reset_session
    redirect_to login_path
  end

  def persist
    auth_session.persist! if logged_in?
    render plain: "OK"
  end

  def begin_password_reset
    return unless request.post?

    user_scope = Postal::Config.oidc.enabled? ? User.with_password : User
    user = user_scope.find_by(email_address: params[:email_address])

    if user.nil?
      redirect_to login_reset_path(return_to: params[:return_to]), alert: "No local user exists with that e-mail address. Please check and try again."
      return
    end

    user.begin_password_reset(params[:return_to])
    redirect_to login_path(return_to: params[:return_to]), notice: "Please check your e-mail and click the link in the e-mail we've sent you."
  end

  def finish_password_reset
    @user = User.where(password_reset_token: params[:token]).where("password_reset_token_valid_until > ?", Time.now).first
    if @user.nil?
      redirect_to login_path(return_to: params[:return_to]), alert: "This link has expired or never existed. Please choose reset password to try again."
    end

    return unless request.post?

    if params[:password].blank?
      flash.now[:alert] = "You must enter a new password"
      return
    end

    @user.password = params[:password]
    @user.password_confirmation = params[:password_confirmation]
    return unless @user.save

    login(@user)
    redirect_to_with_return_to root_path, notice: "Your new password has been set and you've been logged in."
  end

  def ip
    render plain: "ip: #{request.ip} remote ip: #{request.remote_ip}"
  end

  def create_from_oidc
    unless Postal::Config.oidc.enabled?
      raise Postal::Error, "OIDC cannot be used unless enabled in the configuration"
    end

    auth = request.env["omniauth.auth"]
    user = User.find_from_oidc(auth.extra.raw_info, logger: Postal.logger)
    if user.nil?
      redirect_to login_path, alert: "No user was found matching your identity. Please contact your administrator."
      return
    end

    if Postal::Config.oidc.auto_provision_org?
      provision_orgs_from_oidc(user, auth.extra.raw_info)
    end

    login(user)
    flash[:remember_login] = true
    redirect_to_with_return_to root_path
  end

  def oauth_failure
    redirect_to login_path, alert: "An issue occurred while logging you in with OpenID. Please try again later or contact your administrator."
  end

  private

  def provision_orgs_from_oidc(user, raw_info)
    orgs_claim = raw_info["organization"]
    return unless orgs_claim.is_a?(Hash)

    orgs_claim.each do |slug, info|
      org = Organization.find_or_initialize_by(permalink: slug)
      if org.new_record?
        org.name = info.is_a?(Hash) ? (info["name"] || slug) : slug
        org.save!
        org.organization_users.create!(user: user, user_type: "User", admin: true, all_servers: true)
        org.update!(owner: user)
      else
        unless org.organization_users.where(user: user, user_type: "User").exists?
          org.organization_users.create!(user: user, user_type: "User", admin: true, all_servers: true)
        end
      end
    end
  rescue => e
    Postal.logger.error("OIDC org provisioning failed: #{e.message}")
  end

  def require_local_authentication
    return if Postal::Config.oidc.local_authentication_enabled?

    redirect_to login_path, alert: "Local authentication is not enabled"
  end

end
