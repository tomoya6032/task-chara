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
                  text: "この画像の内容を日報として整理してください。必ず以下の4つの項目で構成し、全体の文字数は500〜800文字の範囲内（600文字程度が目安）に収めてください。マークダウン記号（#や##、-など）は一切使わず、項目名を段落の頭に明記してください。親しみやすく分かりやすい自然な文章（丁寧語・ですます調）で記述してください。

【作成する日報の構成】

① 本日の訪問内容
画像の内容から、訪問や業務の概要を大学生でも一読して状況が理解できるレベルに分かりやすく要約して記載してください。

② 課題や修正点
画像の内容から見えてくる課題、今後修正や確認が必要な点があれば、それらを具体的に書き残してください。特になければ「特になし」と記載してください。

③ 今後の方向性
今後の流れとして、次回の訪問時に行うこと、約束ごと、次に発生するタスクを明確にし、チームや大学生スタッフに伝えるようにまとめてください。

④ その他
世間話をしている感じや、現場で談笑している雰囲気が伝わるように記述してください。また、利用者様の様子や、スタッフ自身の感情（嬉しかったこと、感じたこと、安心したことなど）が見えてくるように、温かみを持たせて書き残してください。

※画像内の具体的な固有名詞は一般的な表現に置き換えて、プライバシーに配慮してください。
※4つの項目すべてを含む日報を500〜800文字程度で作成してください。マークダウン記号は使わず、自然で温かみのある丁寧語で記述してください。"
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
          max_tokens: 1200,
          temperature: 0.5 # 温かみのある自然な表現のために適度な創造性を設定
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
            type: "image_ocr",
            status: "completed",
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
          type: "image_ocr",
          status: "error",
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
