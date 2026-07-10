# config/initializers/line_bot.rb
# LINE Bot クライアントを生成するヘルパーメソッド（line-bot-api v2対応）
require "line/bot"

module LineBotClient
  # メッセージ送信用クライアント（channel_access_tokenで初期化）
  def self.client
    # 後方互換性のため LINE_CHANNEL_TOKEN を優先
    token = ENV["LINE_CHANNEL_TOKEN"] || ENV["LINE_CHANNEL_ACCESS_TOKEN"] || Rails.application.credentials.dig(:line, :channel_token)

    if token.blank?
      Rails.logger.warn "[LINE Bot] ⚠️ LINE_CHANNEL_TOKEN not configured"
      # アセットコンパイル時やRakeタスク実行時は警告のみ、エラーで落とさない
      return nil
    end

    Line::Bot::V2::MessagingApi::ApiClient.new(channel_access_token: token)
  end

  # Webhook署名検証・パース用パーサー（channel_secretで初期化）
  def self.webhook_parser
    secret = ENV["LINE_CHANNEL_SECRET"] || Rails.application.credentials.dig(:line, :channel_secret)

    if secret.blank?
      Rails.logger.warn "[LINE Bot] ⚠️ LINE_CHANNEL_SECRET not configured"
      # アセットコンパイル時やRakeタスク実行時は警告のみ、エラーで落とさない
      return nil
    end

    Line::Bot::V2::WebhookParser.new(channel_secret: secret)
  end
end

# アセットコンパイル時以外（通常のアプリ起動時）のみ、エラーチェックを行う
unless ENV["RAILS_GROUPS"] == "assets" || defined?(Rake) && Rake.application.top_level_tasks.include?("assets:precompile")
  token = ENV["LINE_CHANNEL_TOKEN"] || ENV["LINE_CHANNEL_ACCESS_TOKEN"]
  secret = ENV["LINE_CHANNEL_SECRET"]

  # ⭕️ エラーで落とさず、画面に警告を出すだけに留める
  if secret.blank? || token.blank?
    puts "[LINE Bot] ⚠️ LINE credentials not fully configured"
    puts "[LINE Bot]    - TOKEN: #{token.present? ? 'OK' : 'MISSING'}"
    puts "[LINE Bot]    - SECRET: #{secret.present? ? 'OK' : 'MISSING'}"
  else
    puts "[LINE Bot] ✅ LINE credentials configured successfully"
  end
end
