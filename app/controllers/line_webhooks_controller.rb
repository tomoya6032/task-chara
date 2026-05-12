# app/controllers/line_webhooks_controller.rb
# LINE Messaging API Webhook受信エンドポイント（line-bot-api v2対応）
# 友だち追加イベント(follow)でline_user_idをUserに紐付ける
class LineWebhooksController < ApplicationController
  # LINE からの POST はCSRFトークンを持たないため除外
  skip_before_action :verify_authenticity_token

  def callback
    body      = request.body.read
    signature = request.env["HTTP_X_LINE_SIGNATURE"]

    # 署名検証＆イベントパース（InvalidSignatureErrorで400を返す）
    events = LineBotClient.webhook_parser.parse(body: body, signature: signature)

    events.each do |line_event|
      case line_event
      when Line::Bot::V2::Webhook::FollowEvent
        handle_follow(line_event)
      when Line::Bot::V2::Webhook::UnfollowEvent
        handle_unfollow(line_event)
      when Line::Bot::V2::Webhook::MessageEvent
        handle_message(line_event) if line_event.message.is_a?(Line::Bot::V2::Webhook::TextMessageContent)
      end
    end

    head :ok
  rescue Line::Bot::V2::WebhookParser::InvalidSignatureError
    head :bad_request
  end

  private

  # 友だち追加：line_user_id を User に紐付ける
  def handle_follow(event)
    line_user_id = event.source&.user_id
    return unless line_user_id.present?

    if User.exists?(line_user_id: line_user_id)
      Rails.logger.info("[LINE Webhook] Follow: #{line_user_id} already linked.")
      return
    end

    reply_request = Line::Bot::V2::MessagingApi::ReplyMessageRequest.new(
      reply_token: event.reply_token,
      messages: [
        Line::Bot::V2::MessagingApi::TextMessage.new(
          text: "友だち追加ありがとうございます！🎉\n\nリマインド通知を受け取るには、登録済みのメールアドレスを入力してください。\n例）example@example.com"
        )
      ]
    )
    LineBotClient.client.reply_message(reply_message_request: reply_request)
    Rails.logger.info("[LINE Webhook] Follow: prompted #{line_user_id} to enter email.")
  end

  # ブロック・削除：line_user_id をリセット
  def handle_unfollow(event)
    line_user_id = event.source&.user_id
    return unless line_user_id.present?

    user = User.find_by(line_user_id: line_user_id)
    user&.update_columns(line_user_id: nil)
    Rails.logger.info("[LINE Webhook] Unfollow: unlinked #{line_user_id}")
  end

  # テキストメッセージ：メールアドレスの入力を受けて紐付け
  def handle_message(event)
    line_user_id = event.source&.user_id
    text         = event.message.text.to_s.strip
    return unless line_user_id.present? && text.match?(URI::MailTo::EMAIL_REGEXP)

    user = User.find_by(email: text.downcase)

    reply_text =
      if user.nil?
        "入力されたメールアドレスは登録されていません。\n正しいアドレスをご確認ください。"
      elsif user.line_user_id.present? && user.line_user_id != line_user_id
        "このメールアドレスは既に別のLINEアカウントと連携されています。"
      else
        user.update_columns(line_user_id: line_user_id)
        Rails.logger.info("[LINE Webhook] Linked #{line_user_id} to user #{user.id}")
        "✅ 連携完了しました！\nカレンダーの予定を15分前にお知らせします。"
      end

    reply_request = Line::Bot::V2::MessagingApi::ReplyMessageRequest.new(
      reply_token: event.reply_token,
      messages: [ Line::Bot::V2::MessagingApi::TextMessage.new(text: reply_text) ]
    )
    LineBotClient.client.reply_message(reply_message_request: reply_request)
  end
end
