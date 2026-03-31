class ProcessMeetingImageOcrJob < ApplicationJob
  queue_as :default

  def perform(meeting_id_or_session, image_file_path, prompt_template_id = nil)
    Rails.logger.info "🤖 === Starting Meeting Image OCR Job ==="
    Rails.logger.info "📋 Meeting ID or Session: #{meeting_id_or_session}"
    Rails.logger.info "📁 Image file path: #{image_file_path}"
    Rails.logger.info "📝 Custom prompt template ID: #{prompt_template_id || 'Not specified'}"
    Rails.logger.info "✅ Image file exists: #{File.exist?(image_file_path)}"

    # meeting_id_or_sessionがsession_で始まる場合は新規作成
    if meeting_id_or_session.to_s.start_with?("session_")
      session_id = meeting_id_or_session.sub("session_", "")
      meeting_id = nil
      Rails.logger.info "📋 New meeting creation - Session ID: #{session_id}"
    else
      session_id = nil
      meeting_id = meeting_id_or_session
      Rails.logger.info "📋 Existing meeting edit - Meeting ID: #{meeting_id}"
    end

    begin
      client = OpenAI::Client.new

      # 画像をBase64エンコード
      image_data = File.read(image_file_path)
      base64_image = Base64.strict_encode64(image_data)

      # 会議タイプとプロンプトテンプレートを判定
      meeting_type = "support_meeting" # デフォルト値
      selected_prompt_template_id = prompt_template_id # parameterから取得

      if session_id.present?
        # 新規作成の場合
        Rails.logger.info "New meeting creation - using default meeting_type: #{meeting_type}"
        Rails.logger.info "Custom prompt template ID for new meeting: #{selected_prompt_template_id}"
      else
        # 既存議事録の編集の場合、議事録からプロンプトテンプレートIDを取得
        meeting_minute = MeetingMinute.find_by(id: meeting_id)
        if meeting_minute
          meeting_type = meeting_minute.meeting_type
          # パラメータで指定されていない場合は、議事録に保存されたものを使用
          selected_prompt_template_id ||= meeting_minute.prompt_template_id
          Rails.logger.info "Found meeting_minute: type=#{meeting_type}, prompt_template_id=#{selected_prompt_template_id}"
        else
          Rails.logger.warn "Meeting minute not found with ID: #{meeting_id}"
        end
      end

      # カスタムプロンプトテンプレートを取得
      if selected_prompt_template_id.present?
        prompt_template = PromptTemplate.find_by(id: selected_prompt_template_id)
        if prompt_template&.is_active?
          Rails.logger.info "Using selected prompt template: #{prompt_template.name} (ID: #{selected_prompt_template_id})"
        else
          Rails.logger.warn "Selected prompt template not found or inactive, falling back to default"
          prompt_template = PromptTemplate.find_template(
            meeting_type: meeting_type,
            prompt_type: "image_ocr",
            organization_id: nil
          )
        end
      else
        # プロンプトテンプレートが指定されていない場合はデフォルトを使用
        Rails.logger.info "No custom prompt template selected, using default"
        prompt_template = PromptTemplate.find_template(
          meeting_type: meeting_type,
          prompt_type: "image_ocr",
          organization_id: nil
        )
      end

      Rails.logger.info "Using image OCR prompt template: #{prompt_template.name}"

      # OpenAI Vision APIで画像を解析し、議事録形式で出力
      response = client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            {
              role: "system",
              content: prompt_template.system_prompt
            },
            {
              role: "user",
              content: [
                {
                  type: "text",
                  text: prompt_template.user_prompt_template.presence || "この画像から会議内容を読み取り、詳細な議事録として整理してください。"
                },
                {
                  type: "image_url",
                  image_url: {
                    url: "data:image/jpeg;base64,#{base64_image}"
                  }
                }
              ]
            }
          ],
          max_tokens: 3000,  # 画像内容を充実させるため増量
          temperature: 0.5   # 自然さを向上
        }
      )

      processed_text = response.dig("choices", 0, "message", "content")

      if processed_text.present?
        Rails.logger.info "Meeting image OCR completed successfully"

        # WebSocket経由でフロントエンドに結果を送信
        # セッションIDがある場合（新規）とない場合（編集）で分岐
        if session_id.present?
          broadcast_channel = "ai_processing_session_#{session_id}"
          ActionCable.server.broadcast(
            broadcast_channel,
            {
              type: "meeting_image_ocr",
              status: "completed",
              content: processed_text
            }
          )
          Rails.logger.info "[ActionCable] Broadcasting to #{broadcast_channel}"

          # セッション用の一時データ保存（新規作成時）
          Rails.cache.write("temp_meeting_image_ocr_#{session_id}", processed_text, expires_in: 1.hour)
        else
          broadcast_channel = "ai_processing_#{meeting_id}"
          ActionCable.server.broadcast(
            broadcast_channel,
            {
              type: "meeting_image_ocr",
              status: "completed",
              content: processed_text
            }
          )
          Rails.logger.info "[ActionCable] Broadcasting to #{broadcast_channel}"
        end
      else
        raise "画像からの議事録生成に失敗しました"
      end

    rescue => e
      Rails.logger.error "会議画像OCRエラー: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # WebSocket経由でエラーを通知
      if session_id.present?
        broadcast_channel = "ai_processing_session_#{session_id}"
      else
        broadcast_channel = "ai_processing_#{meeting_id}"
      end

      ActionCable.server.broadcast(
        broadcast_channel,
        {
          type: "meeting_image_ocr",
          status: "error",
          error: e.message
        }
      )
      Rails.logger.info "[ActionCable] Error broadcasted to #{broadcast_channel}"
    ensure
      # 一時ファイルを削除
      File.delete(image_file_path) if File.exist?(image_file_path)
    end
  end
end
