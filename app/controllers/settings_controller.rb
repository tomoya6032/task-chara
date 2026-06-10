class SettingsController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
  end

  def update
    @user = current_user
    
    if user_params[:password].present?
      # パスワード変更の場合
      if @user.update_with_password(user_params)
        bypass_sign_in(@user)
        redirect_to settings_path, notice: '設定を更新しました'
      else
        render :show, status: :unprocessable_entity
      end
    else
      # パスワード以外の更新
      if @user.update(user_params.except(:current_password, :password, :password_confirmation))
        redirect_to settings_path, notice: '設定を更新しました'
      else
        render :show, status: :unprocessable_entity
      end
    end
  end

  def unlink_line
    @user = current_user
    
    if @user.line_user_id.present?
      @user.update_columns(line_user_id: nil)
      redirect_to settings_path, notice: 'LINE連携を解除しました'
    else
      redirect_to settings_path, alert: 'LINE連携されていません'
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :current_password, :password, :password_confirmation)
  end
end
