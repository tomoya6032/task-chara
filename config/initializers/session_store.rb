# frozen_string_literal: true

# PWA最適化: ブラウザを閉じても6時間はセッションを保持する設定
# timeout_in（3時間の無操作タイムアウト）と組み合わせて使用
Rails.application.config.session_store :cookie_store,
  key: "_task_character_session",
  expire_after: 6.hours,              # 6時間後にセッション期限切れ（ブラウザを閉じても保持）
  same_site: :lax,                    # CSRF対策とPWA互換性のバランス
  secure: Rails.env.production?,      # 本番環境ではHTTPSのみ
  httponly: true,                     # JavaScriptからのアクセスを防止（XSS対策）
  domain: nil                         # 現在のホストのみに制限（Heroku環境で重要）
