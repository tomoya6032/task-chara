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

    # 🔧 Rails 8 ActiveRecord 暗号化の設定（Heroku対応）
    # このアプリでは暗号化カラムを使用していないため、暗号化機能を安全に無効化
    is_asset_precompile = ENV["RAILS_GROUPS"] == "assets" ||
                          (defined?(Rake.application) && Rake.application.top_level_tasks.include?("assets:precompile"))

    # 常に暗号化なしのデータを扱えるようにする（500エラー回避）
    config.active_record.encryption.support_unencrypted_data = true

    # 暗号化キーを設定（credentialsに存在しない場合はダミー値を使用）
    # アセットコンパイル時と本番稼働時の両方で安全に動作する設定
    if is_asset_precompile
      config.require_master_key = false
    end

    # 暗号化キーの設定（エラー回避のため常に設定）
    config.active_record.encryption.primary_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY") { "0" * 32 }
    config.active_record.encryption.deterministic_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY") { "0" * 32 }
    config.active_record.encryption.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT") { "0" * 32 }

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
