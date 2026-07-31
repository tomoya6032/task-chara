# frozen_string_literal: true

# PWA最適化: iOS Safari PWAでもセッションを3時間保持する設定
Rails.application.config.session_store :cookie_store,
  key: "_task_character_session",
  expire_after: 3.hours,              # 3時間後にセッション期限切れ
  same_site: :lax,                    # CSRF対策とPWA互換性のバランス
  secure: Rails.env.production?,      # 本番環境ではHTTPSのみ
  httponly: true                      # JavaScriptからのアクセスを防止（XSS対策）
