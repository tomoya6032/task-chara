module LineNotifyHelper
  # LINE Notifyが設定されているかチェック
  def line_notify_configured?
    ENV['LINE_NOTIFY_CLIENT_ID'].present? && ENV['LINE_NOTIFY_CLIENT_SECRET'].present?
  end

  # LINE Notifyで通知を送信
  def send_line_notify(user, message)
    return false unless user.line_notify_token.present?

    require 'net/http'
    require 'uri'

    uri = URI.parse('https://notify-api.line.me/api/notify')
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{user.line_notify_token}"
    request.set_form_data(message: message)

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    response.code == '200'
  rescue => e
    Rails.logger.error("LINE Notify送信エラー: #{e.message}")
    false
  end
end
