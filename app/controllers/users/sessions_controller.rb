# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  # Heroku + iOS環境でのCSRFトークン問題の対策
  # ログイン時のみCSRF検証を緩和（セッション作成前のため）
  skip_before_action :verify_authenticity_token, only: [ :create ], if: :json_request?

  # GET /users/sign_in
  def new
    # ログインフォーム表示前にセッションをリフレッシュ
    # 古いCSRFトークンによるエラーを防止
    if request.format.html?
      # 既存のセッションがあれば新しいCSRFトークンを生成
      session[:_csrf_token] = nil if session[:_csrf_token].present?
    end
    super
  end

  # POST /users/sign_in
  def create
    # Deviseのデフォルト処理を実行（自動的にsign_inが呼ばれる）
    super do |resource|
      if resource.persisted?
        # ログイン成功時の詳細ログ（Heroku環境での診断用）
        logger.info "✅ Login successful for user: #{resource.email}"
        logger.info "  - Session ID: #{session.id.inspect}"
        logger.info "  - Request Protocol: #{request.protocol}"
        logger.info "  - Request SSL?: #{request.ssl?}"
        logger.info "  - X-Forwarded-Proto: #{request.headers['X-Forwarded-Proto']}"
        logger.info "  - Secure Cookie: #{Rails.configuration.session_options[:secure]}"
      end
    end
  rescue ActionController::InvalidAuthenticityToken => e
    # CSRFエラーが発生した場合の特別処理
    logger.warn "⚠️ CSRF error during login - attempting recovery"
    logger.warn "⚠️ User-Agent: #{request.user_agent}"

    # セッションをリセットして再度ログインフォームを表示
    reset_session
    flash[:alert] = "ログイン処理中にエラーが発生しました。もう一度お試しください。"
    redirect_to new_user_session_path
  end

  # DELETE /users/sign_out
  # def destroy
  #   super
  # end

  protected

  # ログイン後のリダイレクト先
  # def after_sign_in_path_for(resource)
  #   super(resource)
  # end

  # ログアウト後のリダイレクト先
  # def after_sign_out_path_for(resource_or_scope)
  #   super(resource_or_scope)
  # end

  private

  def json_request?
    request.format.json?
  end
end
