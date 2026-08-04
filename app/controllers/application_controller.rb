class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # 検索エンジンのインデックスを禁止（会員制サイトのため）
  before_action :set_no_index_header

  # Devise認証
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_current_user
  before_action :check_token_limit
  before_action :log_session_debug, if: -> { Rails.env.production? && params[:debug_session].present? }

  # Pundit認可
  include Pundit::Authorization
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # CSRF トークンエラーのハンドリング（PWA/Turbo遷移時の対策）
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_csrf_token_error

  private

  # セッション診断用ログ（本番環境で ?debug_session=1 を付けると詳細ログを出力）
  def log_session_debug
    logger.info "🔍 Session Debug:"
    logger.info "  - Session ID: #{session.id.inspect}"
    logger.info "  - User ID: #{session[:user_id] || current_user&.id}"
    logger.info "  - Request Protocol: #{request.protocol}"
    logger.info "  - Request SSL?: #{request.ssl?}"
    logger.info "  - X-Forwarded-Proto: #{request.headers['X-Forwarded-Proto']}"
    logger.info "  - X-Forwarded-For: #{request.headers['X-Forwarded-For']}"
    logger.info "  - Cookie Header: #{request.headers['Cookie']&.truncate(100)}"
    logger.info "  - Set-Cookie in response: #{response.headers['Set-Cookie']&.truncate(100)}"
    logger.info "  - Force SSL: #{Rails.configuration.force_ssl}"
    logger.info "  - Assume SSL: #{Rails.configuration.assume_ssl}"
    logger.info "  - Session Options: #{Rails.configuration.session_options.inspect}"
  end

  # CSRF トークンエラー時の処理
  def handle_csrf_token_error
    logger.warn "⚠️ CSRF token error detected"
    logger.warn "⚠️ User Agent: #{request.user_agent}"
    logger.warn "⚠️ Request: #{request.method} #{request.path}"
    logger.warn "⚠️ Referer: #{request.referer}"

    # Deviseコントローラーの場合は特別処理（リダイレクトループ防止）
    if devise_controller?
      # ログインページからのエラーの場合、セッションをクリアして再表示
      reset_session

      respond_to do |format|
        format.html do
          flash.now[:alert] = "セキュリティ保護のため、ページを更新してもう一度お試しください。"
          # 元のアクションにリダイレクトせず、エラーページを表示
          render file: "#{Rails.root}/public/422.html", status: :unprocessable_entity, layout: false
        end
        format.json do
          render json: { error: "CSRF token invalid. Please refresh and try again." }, status: :unprocessable_entity
        end
      end
    else
      # 通常のコントローラーの場合はログインページにリダイレクト
      reset_session

      respond_to do |format|
        format.html do
          flash[:alert] = "セキュリティ保護のため、再度ログインしてください。"
          redirect_to new_user_session_path
        end
        format.turbo_stream do
          flash[:alert] = "セキュリティ保護のため、再度ログインしてください。"
          redirect_to new_user_session_path
        end
        format.json do
          render json: { error: "CSRF token invalid. Please login again." }, status: :unprocessable_entity
        end
      end
    end
  end

  # 検索エンジンのインデックスを禁止するHTTPヘッダーを設定
  def set_no_index_header
    response.headers["X-Robots-Tag"] = "noindex, nofollow, noarchive"
  end

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
    unless current_user
      Rails.logger.warn "⚠️ set_character: current_user is nil - User not logged in"
      Rails.logger.warn "⚠️ Redirecting to: #{new_user_session_path}"
      flash[:alert] = "この機能を利用するにはログインが必要です。"
      redirect_to new_user_session_path
      return
    end

    @character = current_user.character
    unless @character
      Rails.logger.error "❌ set_character: Character not found for user #{current_user.id} (#{current_user.email})"
      flash[:alert] = "キャラクターが見つかりません。アカウント設定を確認してください。"
      redirect_to root_path
      nil
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
