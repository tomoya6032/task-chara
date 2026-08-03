# frozen_string_literal: true

# Heroku環境でのセッションCookie保存問題の修正
# X-Forwarded-Proto ヘッダーを確実に認識させる

Rails.application.config.to_prepare do
  # Heroku環境でのHTTPS認識を確実にする
  # X-Forwarded-Proto ヘッダーがある場合、それを信頼する
  Rails.application.config.action_dispatch.x_sendfile_header = nil if Rails.env.production?

  # セッション設定のデバッグログ（本番環境で初回起動時のみ）
  if Rails.env.production? && !defined?(@session_config_logged)
    @session_config_logged = true
    Rails.logger.info "🔒 Session Configuration:"
    Rails.logger.info "  - Store: #{Rails.configuration.session_store}"
    Rails.logger.info "  - Options: #{Rails.configuration.session_options.inspect}"
    Rails.logger.info "  - Force SSL: #{Rails.configuration.force_ssl}"
    Rails.logger.info "  - Assume SSL: #{Rails.configuration.assume_ssl}"
  end
end
