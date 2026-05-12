# config/initializers/line_bot.rb
# LINE Bot クライアントを生成するヘルパーメソッド（line-bot-api v2対応）
require "line/bot"

module LineBotClient
  # メッセージ送信用クライアント（channel_access_tokenで初期化）
  def self.client
    token = ENV["LINE_CHANNEL_TOKEN"] || Rails.application.credentials.dig(:line, :channel_token)
    Line::Bot::V2::MessagingApi::ApiClient.new(channel_access_token: token)
  end

  # Webhook署名検証・パース用パーサー（channel_secretで初期化）
  def self.webhook_parser
    secret = ENV["LINE_CHANNEL_SECRET"] || Rails.application.credentials.dig(:line, :channel_secret)
    Line::Bot::V2::WebhookParser.new(channel_secret: secret)
  end
end
