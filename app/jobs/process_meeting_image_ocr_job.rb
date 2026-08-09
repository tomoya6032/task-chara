class ProcessMeetingImageOcrJob < ApplicationJob
  queue_as :default

  def perform(meeting_id_or_session, blob_signed_id, prompt_template_id = nil)
    Rails.logger.info "🤖 === Starting Meeting Image OCR Job ==="
    Rails.logger.info "📋 Meeting ID or Session: #{meeting_id_or_session}"
    Rails.logger.info "📦 Blob Signed ID: #{blob_signed_id}"
    Rails.logger.info "📝 Custom prompt template ID: #{prompt_template_id || 'Not specified'}"

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

    # Active Storageからblobを取得
    blob = nil
    temp_file = nil
    
    begin
      blob = ActiveStorage::Blob.find_signed(blob_signed_id)
      
      if blob.nil?
        Rails.logger.error "❌ Blob not found with signed ID: #{blob_signed_id}"
        raise "Image blob not found"
      end

      Rails.logger.info "✅ Blob found successfully"
      Rails.logger.info "📊 Blob details:"
      Rails.logger.info "  - ID: #{blob.id}"
      Rails.logger.info "  - Filename: #{blob.filename}"
      Rails.logger.info "  - Content Type: #{blob.content_type}"
      Rails.logger.info "  - Size: #{blob.byte_size} bytes (#{(blob.byte_size.to_f / 1024 / 1024).round(2)}MB)"
      Rails.logger.info "  - Key: #{blob.key}"

      # 一時ファイルにダウンロード（Heroku worker dynoのローカル/tmpに保存）
      file_extension = File.extname(blob.filename.to_s)
      temp_file = Tempfile.new([ "meeting_image_#{blob.id}", file_extension ])
      temp_file.binmode
      
      Rails.logger.info "📥 Downloading blob from S3 to temporary file: #{temp_file.path}"
      
      # ストリーミングでダウンロード（メモリ消費を抑える）
      blob.download do |chunk|
        temp_file.write(chunk)
      end
      temp_file.rewind
      temp_file.close
      
      Rails.logger.info "✅ Blob downloaded successfully to: #{temp_file.path}"
      Rails.logger.info "📊 Downloaded file size: #{File.size(temp_file.path)} bytes"
      
      # ダウンロード後のメモリクリア（ストリーミングバッファを解放）
      GC.start
      Rails.logger.info "🧹 Memory cleanup after blob download"

      client = OpenAI::Client.new

      # 画像をBase64エンコード
      Rails.logger.info "📝 Reading image file for Base64 encoding..."
      image_data = File.read(temp_file.path)
      Rails.logger.info "📝 Encoding image to Base64..."
      base64_image = Base64.strict_encode64(image_data)
      Rails.logger.info "✅ Base64 encoding completed (#{base64_image.length} characters)"
      
      # メモリ解放（Base64エンコード後）
      image_data = nil
      GC.start
      Rails.logger.info "🧹 Memory cleanup after Base64 encoding"

      # 会議タイプとプロンプトテンプレートを判定
      meeting_type = "regular_meeting" # デフォルト値（通常の会議議事録）
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

      # Vision API呼び出し前にメモリをクリア
      GC.start
      Rails.logger.info "🧹 Pre-Vision API memory cleanup"
      Rails.logger.info "📤 Sending image to OpenAI Vision API..."

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

      # メモリ解放（Vision API処理後）
      response = nil
      base64_image = nil
      GC.start
      Rails.logger.info "🧹 Memory cleanup after Vision API processing"

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
      # 一時ファイルを確実に削除（worker dynoのローカル/tmp）
      if temp_file
        begin
          temp_file.close unless temp_file.closed?
          File.delete(temp_file.path) if temp_file.path && File.exist?(temp_file.path)
          Rails.logger.info "🗑️  Temporary file deleted: #{temp_file.path}"
        rescue => e
          Rails.logger.error "Failed to delete temporary file: #{e.message}"
        end
      end

      # Active Storage blobを削除（S3から削除）
      if blob
        begin
          blob.purge
          Rails.logger.info "🗑️  Active Storage blob purged (deleted from S3): #{blob.key}"
        rescue => e
          Rails.logger.error "Failed to purge blob: #{e.message}"
        end
      end

      # 最終メモリクリーンアップ
      GC.start
      Rails.logger.info "🧹 Final memory cleanup completed"
      # 一時ファイルを削除
      File.delete(image_file_path) if File.exist?(image_file_path)
    end
  end
end
