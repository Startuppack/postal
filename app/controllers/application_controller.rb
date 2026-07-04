# frozen_string_literal: true

require "authie/session"

class ApplicationController < ActionController::Base

  protect_from_forgery with: :exception

  before_action :login_required
  before_action :set_timezone

  rescue_from Authie::Session::InactiveSession, with: :auth_session_error
  rescue_from Authie::Session::ExpiredSession, with: :auth_session_error
  rescue_from Authie::Session::BrowserMismatch, with: :auth_session_error

  private

  def login_required
    return if logged_in? && current_user

    # Session authie encore valide mais User ABSENT (compte supprimé au teardown
    # d'un tenant, ou provisioning SCIM-only) : logged_in? reste vrai alors que
    # current_user est nil. Sans ça → 500 (undefined method 'id' for nil) dans
    # append_info_to_payload / set_timezone. On invalide la session périmée et on
    # renvoie au login (où le mode SCIM-only refusera de recréer le compte).
    auth_session.invalidate! if logged_in?
    redirect_to login_path(return_to: request.fullpath)
  end

  def admin_required
    if logged_in?
      unless current_user.admin?
        render plain: "Not permitted"
      end
    else
      redirect_to login_path(return_to: request.fullpath)
    end
  end

  def require_organization_owner
    return if organization.owner == current_user

    redirect_to organization_root_path(organization), alert: "This page can only be accessed by the organization's owner (#{organization.owner.name})"
  end

  def auth_session_error(exception)
    Rails.logger.info "AuthSessionError: #{exception.class}: #{exception.message}"
    redirect_to login_path(return_to: request.fullpath)
  end

  def page_title
    @page_title ||= ["Postal"]
  end
  helper_method :page_title

  def redirect_to_with_return_to(url, *args)
    redirect_to url_with_return_to(url), *args
  end

  def set_timezone
    Time.zone = current_user&.time_zone || "UTC"
  end

  def append_info_to_payload(payload)
    super
    payload[:ip] = request.ip
    # current_user peut être nil même si logged_in? (session périmée d'un User
    # supprimé) — ce hook tourne sur CHAQUE requête, y compris les redirects.
    payload[:user] = current_user&.id
  end

  def url_with_return_to(url)
    return_to = params[:return_to]
    if return_to.blank? ||
       !return_to.start_with?("/") ||
       return_to.start_with?("//", "/\\")
      url_for(url)
    else
      return_to
    end
  end

  def redirect_to_with_json(url, flash_messages = {})
    if url.is_a?(Array) && url[0] == :return_to
      url = url_with_return_to(url[1])
    else
      url = url_for(url)
    end

    flash_messages.each do |key, value|
      flash[key] = value
    end
    respond_to do |wants|
      wants.html { redirect_to url }
      wants.json { render json: { redirect_to: url } }
    end
  end

  def render_form_errors(action_name, object)
    respond_to do |wants|
      wants.html { render action_name }
      wants.json { render json: { form_errors: object.errors.map(&:full_message) }, status: :unprocessable_entity }
    end
  end

  def flash_now(type, message, options = {})
    respond_to do |wants|
      wants.html do
        flash.now[type] = message
        if options[:render_action]
          render options[:render_action]
        end
      end
      wants.json { render json: { flash: { type => message } } }
    end
  end

  def login(user)
    if logged_in?
      auth_session.invalidate!
      reset_session
    end

    create_auth_session(user)
    @current_user = user
  end

end
