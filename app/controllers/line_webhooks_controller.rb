# app/controllers/line_webhooks_controller.rb
# LINE Messaging API Webhook受信エンドポイント（line-bot-api v2対応）
# LINE Login OAuthで連携を行うため、Webhookではunfollowイベントのみ処理
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
      end
    end

    head :ok
  rescue Line::Bot::V2::WebhookParser::InvalidSignatureError
    head :bad_request
  end

  private

  # 友だち追加：案内メッセージを送信
  def handle_follow(event)
    line_user_id = event.source&.user_id
    return unless line_user_id.present?

    # LINE Login OAuth での連携を促すメッセージ
    reply_request = Line::Bot::V2::MessagingApi::ReplyMessageRequest.new(
      reply_token: event.reply_token,
      messages: [
        Line::Bot::V2::MessagingApi::TextMessage.new(
          text: "友だち追加ありがとうございます！🎉\n\nリマインド通知を受け取るには、TaskCharaの設定ページで「LINEと連携する」ボタンを押してください。\n\n※メールアドレスの入力は不要です。ワンクリックで連携完了します。"
        )
      ]
    )
    LineBotClient.client.reply_message(reply_message_request: reply_request)
    Rails.logger.info("[LINE Webhook] Follow: sent OAuth instruction to #{line_user_id}")
  end

  # ブロック・削除：line_user_id をリセット
  def handle_unfollow(event)
    line_user_id = event.source&.user_id
    return unless line_user_id.present?

    user = User.find_by(line_user_id: line_user_id)
    if user
      user.update_columns(line_user_id: nil)
      Rails.logger.info("[LINE Webhook] Unfollow: unlinked #{line_user_id} from user #{user.id}")
    end
  end
end
