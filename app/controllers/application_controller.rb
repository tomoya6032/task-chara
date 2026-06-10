class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Devise認証
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_current_user
  before_action :check_token_limit

  # Pundit認可
  include Pundit::Authorization
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  # Deviseパラメータの許可
  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name ])
  end

  def set_current_user
    @current_user = current_user
    @current_character = current_user&.character
  end

  # 現在のユーザーのキャラクターを取得
  def set_character
    @character = current_user.character
    unless @character
      redirect_to root_path, alert: "キャラクターが見つかりません。"
    end
  end

  # トークン上限チェック
  def check_token_limit
    return unless current_user
    return if devise_controller?
    return if controller_name == "dashboards" && action_name == "show"

    unless current_user.can_use_ai?
      flash[:alert] = "トークン上限に達しています。管理者にお問い合わせください。"
      redirect_to root_path if request.format.html?
    end
  end

  def user_not_authorized
    flash[:alert] = "このアクションを実行する権限がありません。"
    redirect_to(request.referrer || root_path)
  end
end
