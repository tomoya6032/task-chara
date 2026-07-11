require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module TaskCharacter
  require "line/bot"
  require "line-bot-api"

  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # 🔧 アセットコンパイル時の包括的な安全対策（Herokuデプロイ対応）
    # アセットコンパイル時は credentials や暗号化キーの読み込みを完全にスキップ
    is_asset_precompile = ENV["RAILS_GROUPS"] == "assets" ||
                          (defined?(Rake.application) && Rake.application.top_level_tasks.include?("assets:precompile"))

    if is_asset_precompile
      # 1. Master key を要求しない（credentials.yml.enc を読み込まない）
      config.require_master_key = false

      # 2. ActiveRecord の暗号化機能をダミーキーで初期化（エラー回避）
      # Rails 8 のデフォルト暗号化設定が原因でビルドが失敗するのを防ぐ
      config.active_record.encryption.primary_key = "0" * 32  # 32バイトのダミーキー
      config.active_record.encryption.deterministic_key = "0" * 32  # 32バイトのダミーキー
      config.active_record.encryption.key_derivation_salt = "0" * 32  # 32バイトのダミーソルト
    end

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Asia/Tokyo"
    # config.eager_load_paths << Rails.root.join("extras")

    # Set default locale to Japanese
    config.i18n.default_locale = :ja
    config.i18n.available_locales = [ :ja, :en ]
  end
end
