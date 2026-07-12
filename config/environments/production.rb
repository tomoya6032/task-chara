require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # 🔧 アセットコンパイル時の特別な設定（Herokuデプロイ対策）
  # アセットコンパイル時は credentials や DB 接続を必要としない
  is_asset_precompile = ENV["RAILS_GROUPS"] == "assets" ||
                        (defined?(Rake.application) && Rake.application.top_level_tasks.include?("assets:precompile"))

  if is_asset_precompile
    # アセットコンパイル時は master key を要求しない（credentialsを読まない）
    config.require_master_key = false
    # アセットコンパイル時は eager load を無効化（モデルやルーティングを読み込まない）
    config.eager_load = false
    # アセットコンパイル時は ActiveStorage を無効化（AWS S3接続しない）
    config.active_storage.service = :local
  else
    # 通常起動時のみ master key を要求
    config.require_master_key = true
    # 通常起動時は eager load を有効化
    config.eager_load = true
    # 通常起動時は AWS S3 を使用
    config.active_storage.service = :amazon
  end

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # 🔧 メール配信設定（SendGrid環境変数の有無で自動切り替え）
  # SendGridが設定されていない場合はメール配信を無効化（500エラー回避）
  sendgrid_configured = ENV["SENDGRID_USERNAME"].present? && ENV["SENDGRID_PASSWORD"].present?

  if sendgrid_configured
    # SendGrid設定あり：メール配信を有効化
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.perform_deliveries = true

    config.action_mailer.smtp_settings = {
      address: "smtp.sendgrid.net",
      port: 587,
      domain: ENV["APP_HOST"] || "herokuapp.com",
      user_name: ENV["SENDGRID_USERNAME"],
      password: ENV["SENDGRID_PASSWORD"],
      authentication: :plain,
      enable_starttls_auto: true
    }
  else
    # SendGrid未設定：メール配信を無効化
    config.action_mailer.raise_delivery_errors = false
    config.action_mailer.perform_deliveries = false
    puts "[Mailer] ⚠️ SendGrid not configured, email delivery disabled"
  end

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = {
    host: ENV["APP_HOST"] || "localhost:3000",
    protocol: "https"
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  config.hosts = [
    ENV["APP_HOST"],              # Your Heroku app domain
    /.*\.herokuapp\.com/,         # All Heroku subdomains
    "localhost"                   # For local testing
  ].compact
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
