# app/services/line_bot_service.rb
# LINE Messaging API の送信ロジックを集約するサービスクラス（line-bot-api v2対応）
# ActiveJob から呼び出すことを前提に設計
class LineBotService
  def initialize
    @client = ::LineBotClient.client
  rescue NameError => e
    Rails.logger.error("[LineBotService] NameError while building LINE client: #{e.message}")
    Rails.logger.error("[LineBotService] ::LineBotClient defined?: #{defined?(::LineBotClient).present?}")
    Rails.logger.error("[LineBotService] ::Line::Bot defined?: #{defined?(::Line::Bot).present?}")
    Rails.logger.error("[LineBotService] backtrace: #{Array(e.backtrace).first(5).join(' | ')}")
    @client = nil
  end

  # テキストメッセージを送信
  # @param line_user_id [String] 送信先のLINEユーザーID（Uで始まる文字列）
  # @param text [String] 送信するテキスト（最大5000文字）
  # @return [Boolean] 送信成功かどうか
  def send_message(line_user_id, text)
    raise ArgumentError, "line_user_id is blank" if line_user_id.blank?
    raise ArgumentError, "text is blank"         if text.blank?
    raise StandardError, "LINE client is not initialized" if @client.nil?

    request = ::Line::Bot::V2::MessagingApi::PushMessageRequest.new(
      to: line_user_id,
      messages: [
        ::Line::Bot::V2::MessagingApi::TextMessage.new(text: text.to_s.truncate(5000))
      ]
    )
    @client.push_message(push_message_request: request)
    Rails.logger.info("[LineBotService] Sent to #{line_user_id}: #{text.truncate(50)}")
    true
  rescue ArgumentError => e
    Rails.logger.error("[LineBotService] Invalid argument: #{e.message}")
    false
  rescue => e
    Rails.logger.error("[LineBotService] Unexpected error: #{e.class} - #{e.message}")
    false
  end

  # カレンダーイベントの開始15分前リマインドメッセージを送信
  # @param line_user_id [String] 送信先のLINEユーザーID
  # @param event [Event] リマインド対象のイベント
  # @return [Boolean] 送信成功かどうか
  def send_event_reminder(line_user_id, event)
    start_str = event.start_time.strftime("%m月%d日 %H:%M")
    text = <<~TEXT.strip
      ⏰ リマインド
      「#{event.title}」の時間が近づいています。
      開始時刻：#{start_str}
      準備はよろしいですか？
    TEXT
    send_message(line_user_id, text)
  end

  # タスク期限72時間前のリマインドメッセージを送信
  # @param line_user_id [String] 送信先のLINEユーザーID
  # @param task [Task] リマインド対象のタスク
  # @return [Boolean] 送信成功かどうか
  def send_task_due_reminder(line_user_id, task)
    due_str = task.due_date.present? ? task.due_date.strftime("%m月%d日 %H:%M") : "期限なし"
    text = <<~TEXT.strip
      ⏰ 期限72時間前リマインド
      タスク「#{task.title}」の期限が近づいています。
      期限：#{due_str}
      早めに着手しておきましょう！
    TEXT
    send_message(line_user_id, text)
  end

  # credentials の設定確認（接続テスト用）
  # @return [Boolean] 認証情報が揃っているか
  def self.credentials_configured?
    secret = ENV["LINE_CHANNEL_SECRET"] || Rails.application.credentials.dig(:line, :channel_secret)
    token  = ENV["LINE_CHANNEL_TOKEN"]  || Rails.application.credentials.dig(:line, :channel_token)
    secret.present? && token.present?
  end
end
