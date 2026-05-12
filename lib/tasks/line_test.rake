# lib/tasks/line_test.rake
# 使い方:
#   rails "line:test_send[YOUR_LINE_USER_ID,テストメッセージ]"
#   rails line:check_credentials
namespace :line do
  desc "指定したLINEユーザーIDにテストメッセージを送信する"
  task :test_send, [ :line_user_id, :message ] => :environment do |_t, args|
    line_user_id = args[:line_user_id]
    message      = args[:message] || "【テスト】TaskCharacterからのテスト送信です 🎉"

    unless line_user_id.present?
      puts "❌ エラー: LINE User IDを指定してください"
      puts "  使い方: rails \"line:test_send[YOUR_LINE_USER_ID,メッセージ]\""
      exit 1
    end

    unless LineBotService.credentials_configured?
      puts "❌ エラー: LINE credentialsが設定されていません"
      puts "  bin/rails credentials:edit で以下を設定してください:"
      puts "  line:"
      puts "    channel_secret: \"your_channel_secret\""
      puts "    channel_token:  \"your_channel_token\""
      exit 1
    end

    puts "📤 送信先: #{line_user_id}"
    puts "📝 メッセージ: #{message}"
    puts "送信中..."

    service = LineBotService.new
    result  = service.send_message(line_user_id, message)

    if result
      puts "✅ 送信成功！LINEを確認してください。"
    else
      puts "❌ 送信失敗。log/development.log を確認してください。"
      exit 1
    end
  end

  desc "LINE credentialsの設定状況を確認する"
  task check_credentials: :environment do
    if LineBotService.credentials_configured?
      puts "✅ LINE credentials は正しく設定されています。"
    else
      puts "❌ LINE credentials が設定されていません。"
      puts "  bin/rails credentials:edit で以下を追記してください:"
      puts ""
      puts "  line:"
      puts "    channel_id: \"your_channel_id\""
      puts "    channel_secret: \"your_channel_secret\""
      puts "    channel_token: \"your_channel_token\""
    end
  end
end
