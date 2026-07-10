# config/initializers/line_bot.rb
# LINE Bot クライアントを生成するヘルパーメソッド（line-bot-api v2対応）
require "line/bot"

module LineBotClient
  # メッセージ送信用クライアント（channel_access_tokenで初期化）
  def self.client
    # 後方互換性のため LINE_CHANNEL_TOKEN を優先
    token = ENV["LINE_CHANNEL_TOKEN"] || ENV["LINE_CHANNEL_ACCESS_TOKEN"] || Rails.application.credentials.dig(:line, :channel_token)

    if token.blank?
      Rails.logger.error "[LINE Bot] LINE_CHANNEL_TOKEN not configured"
      raise "LINE_CHANNEL_TOKEN is not set. Please configure environment variables."
    end

    Line::Bot::V2::MessagingApi::ApiClient.new(channel_access_token: token)
  end

  # Webhook署名検証・パース用パーサー（channel_secretで初期化）
  def self.webhook_parser
    secret = ENV["LINE_CHANNEL_SECRET"] || Rails.application.credentials.dig(:line, :channel_secret)

    if secret.blank?
      Rails.logger.error "[LINE Bot] LINE_CHANNEL_SECRET not configured"
      raise "LINE_CHANNEL_SECRET is not set. Please configure environment variables."
    end

    Line::Bot::V2::WebhookParser.new(channel_secret: secret)
  end
end

# 起動時に設定を確認（本番環境のみ）
if Rails.env.production?
  begin
    token = ENV["LINE_CHANNEL_TOKEN"] || ENV["LINE_CHANNEL_ACCESS_TOKEN"]
    secret = ENV["LINE_CHANNEL_SECRET"]

    if token.present? && secret.present?
      Rails.logger.info "[LINE Bot] ✅ LINE credentials configured successfully"
    else
      Rails.logger.warn "[LINE Bot] ⚠️  LINE credentials not fully configured"
      Rails.logger.warn "[LINE Bot]    - TOKEN: #{token.present? ? 'OK' : 'MISSING'}"
      Rails.logger.warn "[LINE Bot]    - SECRET: #{secret.present? ? 'OK' : 'MISSING'}"
    end
  rescue => e
    Rails.logger.error "[LINE Bot] ❌ Error checking LINE configuration: #{e.message}"
  end
end
