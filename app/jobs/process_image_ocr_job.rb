class ProcessImageOcrJob < ApplicationJob
  queue_as :default

  def perform(activity_id, image_path)
    Rails.logger.info "=== OCR Job Started for activity_id: #{activity_id} ==="
    Rails.logger.info "Image path: #{image_path}"
    Rails.logger.info "File exists: #{File.exist?(image_path)}"
    
    begin
      # OpenAI Vision APIで画像を分析
      client = OpenAI::Client.new
      Rails.logger.info "OpenAI client initialized"
      
      # 画像をBase64エンコード
      image_data = File.read(image_path)
      Rails.logger.info "Image file size: #{image_data.size} bytes"
      
      # 画像形式を判定
      image_format = case image_data[0, 4]
      when "\xFF\xD8\xFF".b
        "jpeg"
      when "\x89PNG".b
        "png"
      when "GIF8".b
        "gif"
      when "RIFF".b
        "webp"
      else
        "jpeg" # デフォルト
      end
      
      Rails.logger.info "Detected image format: #{image_format}"
      
      base64_image = Base64.strict_encode64(image_data)
      Rails.logger.info "Base64 encoding completed"
      
      Rails.logger.info "Sending request to OpenAI Vision API..."
      response = client.chat(
        parameters: {
          model: "gpt-4o", # gpt-4oが現在の推奨モデル
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "text",
                  text: "この画像の内容を業務報告書として適切な形で要約してください。画像に含まれる情報を参考にして、以下の観点で報告書を作成してください：

1. 訪問・面談・会議などの業務活動の概要
2. 相談内容や議題の要点（具体的な内容は要約形式で）
3. 実施した支援や対応の概要
4. 気づいた点や今後の課題
5. その他特筆すべき事項

※画像内のテキストをそのまま転写するのではなく、業務報告として適切に整理・要約してください。個人情報や機密情報に該当する可能性のある具体的な固有名詞は避け、一般的な表現に置き換えてください。"
                },
                {
                  type: "image_url",
                  image_url: {
                    url: "data:image/#{image_format};base64,#{base64_image}",
                    detail: "high"
                  }
                }
              ]
            }
          ],
          max_tokens: 1500,
          temperature: 0.3 # 創造性を少し上げて報告書らしい表現にする
        }
      )
      
      Rails.logger.info "OpenAI API response received"
      Rails.logger.info "Full response: #{response.inspect}"
      
      extracted_text = response.dig("choices", 0, "message", "content")
      Rails.logger.info "Extracted text length: #{extracted_text&.length || 0} characters"
      Rails.logger.info "Extracted text preview: #{extracted_text&.[](0, 200) || 'No content'}"
      
      if extracted_text.present?
        Rails.logger.info "=== OCR completed successfully, broadcasting result ==="
        Rails.logger.info "Broadcasting to channel: ai_processing_#{activity_id}"
        Rails.logger.info "Content preview: #{extracted_text[0..100]}..."
        
        # WebSocket経由でフロントエンドに結果を送信
        ActionCable.server.broadcast(
          "ai_processing_#{activity_id}",
          {
            type: 'image_ocr',
            status: 'completed',
            content: extracted_text
          }
        )
        Rails.logger.info "Broadcast sent successfully"
      else
        raise "文字起こしに失敗しました - extracted_text is blank"
      end
      
    rescue => e
      Rails.logger.error "=== OCR processing error ==="
      Rails.logger.error "Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      ActionCable.server.broadcast(
        "ai_processing_#{activity_id}",
        {
          type: 'image_ocr',
          status: 'error',
          error: e.message
        }
      )
    ensure
      # 一時ファイルをクリーンアップ
      if File.exist?(image_path)
        File.delete(image_path)
        Rails.logger.info "Temporary file deleted: #{image_path}"
      end
      Rails.logger.info "=== OCR Job Finished ==="
    end
  end
end