# config/initializers/openai.rb

# 本番環境のビルド（アセットコンパイル）時は、OpenAIの初期化をスキップする
return if ENV["RAILS_GROUPS"] == "assets" || (defined?(Rake) && Rake.application.top_level_tasks.include?("assets:precompile"))

OpenAI.configure do |config|
  config.access_token = ENV["OPENAI_API_KEY"] || Rails.application.credentials.dig(:openai, :api_key) || ENV["OPENAI_ACCESS_TOKEN"]
  config.log_errors = Rails.env.development?
  config.request_timeout = 600
  # 最新のAPI仕様に合わせた設定
  config.uri_base = "https://api.openai.com/"
  config.api_version = "v1"
end
