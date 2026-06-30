# frozen_string_literal: true

class UsersController < ApplicationController

  before_action :admin_required
  before_action { params[:id] && @user = User.find_by!(uuid: params[:id]) }
  skip_before_action :admin_required, only: [:stop_impersonating]

  def index
    @users = User.order(:first_name, :last_name).includes(:organization_users)
  end

  def new
    @user = User.new(admin: true)
  end

  def edit
  end

  def create
    @user = User.new(params.require(:user).permit(:email_address, :first_name, :last_name, :password, :password_confirmation, :admin, organization_ids: []))
    if @user.save
      redirect_to_with_json :users, notice: "#{@user.name} has been created successfully."
    else
      render_form_errors "new", @user
    end
  end

  def update
    @user.attributes = params.require(:user).permit(:email_address, :first_name, :last_name, :admin, organization_ids: [])

    if @user == current_user && !@user.admin?
      respond_to do |wants|
        wants.html { redirect_to users_path, alert: "You cannot change your own admin status" }
        wants.json { render json: { form_errors: ["You cannot change your own admin status"] }, status: :unprocessable_entity }
      end
      return
    end

    if @user.save
      redirect_to_with_json :users, notice: "Permissions for #{@user.name} have been updated successfully."
    else
      render_form_errors "edit", @user
    end
  end

  def destroy
    if @user == current_user
      redirect_to_with_json :users, alert: "You cannot delete your own user."
      return
    end

    @user.destroy!
    redirect_to_with_json :users, notice: "#{@user.name} has been removed"
  end

  def impersonate
    if @user == real_user
      redirect_to users_path, alert: "You cannot impersonate yourself."
      return
    end
    if @user.organization_users.empty?
      redirect_to users_path, alert: "#{@user.name} is not in any organization."
      return
    end
    auth_session.set(:impersonating_user_id, @user.id)
    redirect_to root_path, notice: "Now impersonating #{@user.name}."
  end

  def stop_impersonating
    unless impersonating?
      redirect_to root_path
      return
    end
    auth_session.set(:impersonating_user_id, nil)
    redirect_to users_path, notice: "Impersonation ended."
  end

end
