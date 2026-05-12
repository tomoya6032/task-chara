# app/services/line_messaging_service.rb（line-bot-api v2対応）
class LineMessagingService
  def initialize
    @client = LineBotClient.client
  end

  # テキストメッセージを送信
  # @param line_user_id [String] 送信先のLINEユーザーID
  # @param text [String] 送信するテキスト
  # @return [Boolean] 成功したかどうか
  def send_text(line_user_id, text)
    request = Line::Bot::V2::MessagingApi::PushMessageRequest.new(
      to: line_user_id,
      messages: [ Line::Bot::V2::MessagingApi::TextMessage.new(text: text) ]
    )
    @client.push_message(push_message_request: request)
    true
  rescue => e
    Rails.logger.error("[LINE] send_text failed: #{e.class} - #{e.message}")
    false
  end

  # イベントリマインドメッセージを送信
  # @param line_user_id [String] 送信先のLINEユーザーID
  # @param event [Event] リマインド対象のイベント
  def send_event_reminder(line_user_id, event)
    start_str = event.start_time.strftime("%H:%M")
    text = "⏰ リマインド\n「#{event.title}」の時間が近づいています。\n開始時刻：#{start_str}\n準備はよろしいですか？"
    send_text(line_user_id, text)
  end
end
