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

    # 🔧 アセットコンパイル時の安全対策
    # アセットコンパイル時は credentials の読み込みを完全にスキップ
    if ENV["RAILS_GROUPS"] == "assets" || (defined?(Rake) && Rake.application.top_level_tasks.include?("assets:precompile"))
      config.require_master_key = false
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
