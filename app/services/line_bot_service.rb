# app/services/line_bot_service.rb
# LINE Messaging API の送信ロジックを集約するサービスクラス（line-bot-api v2対応）
# ActiveJob から呼び出すことを前提に設計
class LineBotService
  def initialize
    @client = LineBotClient.client
  end

  # テキストメッセージを送信
  # @param line_user_id [String] 送信先のLINEユーザーID（Uで始まる文字列）
  # @param text [String] 送信するテキスト（最大5000文字）
  # @return [Boolean] 送信成功かどうか
  def send_message(line_user_id, text)
    raise ArgumentError, "line_user_id is blank" if line_user_id.blank?
    raise ArgumentError, "text is blank"         if text.blank?

    # メッセージリクエストを作成
    message = Line::Bot::V2::MessagingApi::TextMessage.new(text: text.to_s.truncate(5000))
    request = Line::Bot::V2::MessagingApi::PushMessageRequest.new(
      to: line_user_id,
      messages: [ message ]
    )

    Rails.logger.info("[LineBotService] 送信開始 | ユーザーID: #{line_user_id} | メッセージ: #{text.truncate(50)}")
    Rails.logger.debug("[LineBotService] リクエスト詳細: #{request.inspect}")

    # プッシュメッセージを送信（HTTPレスポンスを取得）
    response_body, status_code, headers = @client.push_message_with_http_info(
      push_message_request: request
    )

    Rails.logger.info("[LineBotService] LINE APIレスポンス | ステータス: #{status_code}")
    Rails.logger.debug("[LineBotService] レスポンスボディ: #{response_body.inspect}")
    Rails.logger.debug("[LineBotService] レスポンスヘッダー: #{headers.inspect}")

    # エラー時は生のJSONレスポンスも出力
    if status_code != 200 && response_body.is_a?(Line::Bot::V2::MessagingApi::ErrorResponse)
      Rails.logger.error("[LineBotService] ⚠️ エラーレスポンス詳細:")
      Rails.logger.error("  - message: #{response_body.message}")
      Rails.logger.error("  - details: #{response_body.details.inspect}")
    end

    # ステータスコードに応じた処理
    case status_code
    when 200
      Rails.logger.info("[LineBotService] ✅ 送信成功 | ユーザーID: #{line_user_id}")
      true
    when 400
      Rails.logger.error("[LineBotService] ❌ 400 Bad Request | エラー: #{response_body.message rescue response_body} | 詳細: #{response_body.details rescue 'なし'}")
      false
    when 403
      Rails.logger.error("[LineBotService] ❌ 403 Forbidden | アクセストークンが無効またはユーザーがブロック | エラー: #{response_body.message rescue response_body}")
      false
    when 409
      Rails.logger.error("[LineBotService] ❌ 409 Conflict | エラー: #{response_body.message rescue response_body}")
      false
    when 429
      Rails.logger.error("[LineBotService] ❌ 429 Rate Limit Exceeded | レート制限超過 | エラー: #{response_body.message rescue response_body}")
      false
    else
      Rails.logger.error("[LineBotService] ❌ 予期しないステータスコード: #{status_code} | レスポンス: #{response_body}")
      false
    end

  rescue ArgumentError => e
    Rails.logger.error("[LineBotService] ❌ 引数エラー: #{e.message}")
    false
  rescue => e
    Rails.logger.error("[LineBotService] ❌ 予期しないエラー: #{e.class} - #{e.message}")
    Rails.logger.error("[LineBotService] バックトレース: #{e.backtrace.first(5).join("\n")}")
    false
  end

  # カレンダーイベントの開始15分前リマインドメッセージを送信
  # @param line_user_id [String] 送信先のLINEユーザーID
  # @param event [Event] リマインド対象のイベント
  # @return [Boolean] 送信成功かどうか
  def send_event_reminder(line_user_id, event)
    start_str = event.start_time.strftime("%m月%d日 %H:%M")
    category_name = event.display_category_name || "未設定"

    timing_label = case event.reminder_minutes
    when 30   then "30分前"
    when 60   then "1時間前"
    when 180  then "3時間前"
    when 1440 then "1日前"
    when 4320 then "3日前"
    else "#{event.reminder_minutes}分前"
    end

    text = <<~TEXT.strip
      ⏰ リマインド（#{timing_label}）

      【カテゴリ】 #{category_name}
      【件名】 #{event.title}
      【開始時刻】 #{start_str}

      準備はよろしいですか？
    TEXT
    send_message(line_user_id, text)
  end

  # タスクの期限72時間前リマインドメッセージを送信
  # @param line_user_id [String] 送信先のLINEユーザーID
  # @param task [Task] リマインド対象のタスク
  # @return [Boolean] 送信成功かどうか
  def send_task_due_reminder(line_user_id, task)
    due_str = task.due_date.present? ? task.due_date.strftime("%m月%d日 %H:%M") : "期限なし"
    category_name = task.category_display || "未設定"

    text = <<~TEXT.strip
      🔔 タスクの期限が近づいています（72時間前）

      【カテゴリ】 #{category_name}
      【タスク名】 #{task.title}
      【期限】 #{due_str}

      準備を進めておきましょう！
    TEXT
    send_message(line_user_id, text)
  end

  # credentials の設定確認（接続テスト用）
  # @return [Boolean] 認証情報が揃っているか
  def self.credentials_configured?
    secret = ENV["LINE_CHANNEL_SECRET"] || Rails.application.credentials.dig(:line, :channel_secret)
    # 後方互換性のため LINE_CHANNEL_TOKEN を優先
    token  = ENV["LINE_CHANNEL_TOKEN"] || ENV["LINE_CHANNEL_ACCESS_TOKEN"] || Rails.application.credentials.dig(:line, :channel_token)
    secret.present? && token.present?
  end
end
