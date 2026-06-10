# app/controllers/line_login_controller.rb
# LINE Login OAuth認証によるLINEユーザーIDの取得・紐付け
class LineLoginController < ApplicationController
  before_action :authenticate_user!, except: [ :callback ]

  # LINE Login OAuth認証開始
  def authorize
    # LINE Login Channel ID（環境変数またはcredentials）
    channel_id = ENV["LINE_LOGIN_CHANNEL_ID"] || Rails.application.credentials.dig(:line_login, :channel_id)

    unless channel_id.present?
      redirect_to settings_path, alert: "LINE連携の設定が完了していません。管理者にお問い合わせください。"
      return
    end

    # コールバックURL
    redirect_uri = line_login_callback_url

    # CSRF対策のためのstate生成
    state = SecureRandom.hex(16)
    session[:line_login_state] = state
    session[:line_login_user_id] = current_user.id

    # LINE Login 認可エンドポイント
    # scope: profile でユーザーID、表示名、プロフィール画像を取得可能
    authorize_url = "https://access.line.me/oauth2/v2.1/authorize?" \
                    "response_type=code&" \
                    "client_id=#{channel_id}&" \
                    "redirect_uri=#{CGI.escape(redirect_uri)}&" \
                    "state=#{state}&" \
                    "scope=profile"

    redirect_to authorize_url, allow_other_host: true
  end

  # LINE Login OAuthコールバック
  def callback
    # stateの検証
    if params[:state] != session[:line_login_state]
      redirect_to settings_path, alert: "LINE連携に失敗しました（不正なリクエスト）"
      return
    end

    # ユーザー取得
    user_id = session[:line_login_user_id]
    user = User.find_by(id: user_id)

    unless user
      redirect_to settings_path, alert: "セッションが切れました。もう一度お試しください。"
      return
    end

    # エラーチェック
    if params[:error].present?
      redirect_to settings_path, alert: "LINE連携をキャンセルしました: #{params[:error]}"
      return
    end

    # 認可コード取得
    code = params[:code]

    # アクセストークン取得
    token_response = exchange_code_for_token(code)

    if token_response["access_token"].present?
      access_token = token_response["access_token"]

      # LINEユーザー情報取得
      profile = get_line_profile(access_token)

      if profile && profile["userId"].present?
        line_user_id = profile["userId"]

        # 既に別のユーザーが同じLINEアカウントを連携していないかチェック
        existing_user = User.find_by(line_user_id: line_user_id)
        if existing_user && existing_user.id != user.id
          redirect_to settings_path, alert: "このLINEアカウントは既に別のユーザーと連携されています。"
          return
        end

        # line_user_idを保存
        user.update(line_user_id: line_user_id)

        # セッションクリア
        session.delete(:line_login_state)
        session.delete(:line_login_user_id)

        redirect_to settings_path, notice: "LINE連携が完了しました！カレンダーの予定がリマインドされます。"
      else
        redirect_to settings_path, alert: "LINEユーザー情報の取得に失敗しました。"
      end
    else
      error_message = token_response["error_description"] || token_response["error"] || "不明なエラー"
      redirect_to settings_path, alert: "LINE連携に失敗しました: #{error_message}"
    end
  end

  private

  # 認可コードをアクセストークンと交換
  def exchange_code_for_token(code)
    require "net/http"
    require "uri"
    require "json"

    channel_id = ENV["LINE_LOGIN_CHANNEL_ID"] || Rails.application.credentials.dig(:line_login, :channel_id)
    channel_secret = ENV["LINE_LOGIN_CHANNEL_SECRET"] || Rails.application.credentials.dig(:line_login, :channel_secret)

    uri = URI.parse("https://api.line.me/oauth2/v2.1/token")

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/x-www-form-urlencoded"
    request.set_form_data(
      grant_type: "authorization_code",
      code: code,
      redirect_uri: line_login_callback_url,
      client_id: channel_id,
      client_secret: channel_secret
    )

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("[LINE Login] Token exchange error: #{e.message}")
    { "error" => e.message }
  end

  # LINEプロフィール情報取得
  def get_line_profile(access_token)
    require "net/http"
    require "uri"
    require "json"

    uri = URI.parse("https://api.line.me/v2/profile")

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{access_token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.code == "200"
      JSON.parse(response.body)
    else
      Rails.logger.error("[LINE Login] Profile fetch error: #{response.code} - #{response.body}")
      nil
    end
  rescue StandardError => e
    Rails.logger.error("[LINE Login] Profile fetch error: #{e.message}")
    nil
  end
end
