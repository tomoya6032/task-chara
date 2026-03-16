# OpenAI API接続テスト用のRakeタスク

namespace :support_report do
  desc "OpenAI API接続をテスト"
  task test_openai: :environment do
    puts "OpenAI API接続テストを開始..."
    
    begin
      client = OpenAI::Client.new
      
      if ENV['OPENAI_API_KEY'].blank?
        puts "❌ エラー: OPENAI_API_KEYが設定されていません"
        puts "   .envファイルにOPENAI_API_KEY=your-key-hereを追加してください"
        exit 1
      end
      
      puts "🔧 APIキー: #{ENV['OPENAI_API_KEY'][0..10]}..." if ENV['OPENAI_API_KEY']
      
      # シンプルなテストリクエスト
      response = client.chat(
        parameters: {
          model: "gpt-3.5-turbo",
          messages: [{ role: "user", content: "Hello, this is a test message." }],
          max_tokens: 50
        }
      )
      
      puts "✅ OpenAI API接続成功!"
      puts "   レスポンス: #{response.dig("choices", 0, "message", "content")}"
      
    rescue => e
      puts "❌ OpenAI API接続エラー:"
      puts "   エラー内容: #{e.message}"
      puts "   解決策:"
      puts "   1. APIキーが正しいか確認"
      puts "   2. OpenAI アカウントに十分な残高があるか確認"
      puts "   3. インターネット接続を確認"
    end
  end
end