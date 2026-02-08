# config/initializers/openai.rb
OpenAI.configure do |config|
  config.access_token = Rails.application.credentials.dig(:openai, :api_key) || ENV["OPENAI_ACCESS_TOKEN"]
  config.log_errors = Rails.env.development?
  config.request_timeout = 240 # Optional
end
