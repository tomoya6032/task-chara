# config/initializers/openai.rb
OpenAI.configure do |config|
  config.access_token = ENV["OPENAI_API_KEY"] || Rails.application.credentials.dig(:openai, :api_key) || ENV["OPENAI_ACCESS_TOKEN"]
  config.log_errors = Rails.env.development?
  config.request_timeout = 240
  # 最新のAPI仕様に合わせた設定
  config.uri_base = "https://api.openai.com/"
  config.api_version = "v1"
end
