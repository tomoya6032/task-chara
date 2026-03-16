namespace :vision do
  desc "Test OpenAI Vision API with different models"
  task test_models: :environment do
    puts "Testing OpenAI Vision API with different models..."
    
    # テスト用の小さな画像（1x1ピクセルの白い画像）
    test_image = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=='
    
    models = ['gpt-4-vision-preview', 'gpt-4o']
    
    models.each do |model|
      puts "\n=== Testing model: #{model} ==="
      
      begin
        client = OpenAI::Client.new
        
        response = client.chat(
          parameters: {
            model: model,
            messages: [
              {
                role: "user",
                content: [
                  {
                    type: "text",
                    text: "この画像に何が写っていますか？日本語で答えてください。"
                  },
                  {
                    type: "image_url",
                    image_url: {
                      url: "data:image/png;base64,#{test_image}",
                      detail: "high"
                    }
                  }
                ]
              }
            ],
            max_tokens: 300,
            temperature: 0.1
          }
        )
        
        result = response.dig("choices", 0, "message", "content")
        puts "✅ #{model}: #{result}"
        
      rescue => e
        puts "❌ #{model}: ERROR - #{e.message}"
        puts "   Full error: #{e.class} - #{e.backtrace.first(3).join('\n   ')}"
      end
    end
    
    puts "\n=== Test completed ==="
  end
end