class ProcessMeetingVoiceTranscriptionJob < ApplicationJob
  queue_as :default

  def perform(meeting_id_or_session, blob_signed_id, prompt_template_id = nil)
    Rails.logger.info "🤖 === Starting Meeting Voice Transcription Job ==="
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
        raise "Audio blob not found"
      end

      Rails.logger.info "✅ Blob found successfully"
      Rails.logger.info "📊 Blob details:"
      Rails.logger.info "  - ID: #{blob.id}"
      Rails.logger.info "  - Filename: #{blob.filename}"
      Rails.logger.info "  - Content Type: #{blob.content_type}"
      Rails.logger.info "  - Size: #{blob.byte_size} bytes (#{(blob.byte_size.to_f / 1024 / 1024).round(2)}MB)"
      Rails.logger.info "  - Key: #{blob.key}"

      # M4Aファイルの特別な処理ログ
      if blob.filename.to_s.downcase.end_with?(".m4a")
        Rails.logger.info "🎵 Processing M4A file (iPhone/iOS format)"
      end

      # 一時ファイルにダウンロード（Heroku worker dynoのローカル/tmpに保存）
      file_extension = File.extname(blob.filename.to_s)
      temp_file = Tempfile.new([ "meeting_voice_#{blob.id}", file_extension ])
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

      # 他のセクションと同じ方法で OpenAI クライアントを作成
      client = OpenAI::Client.new
      Rails.logger.info "🔗 OpenAI client initialized successfully"

      Rails.logger.info "📤 Sending audio file to OpenAI Whisper API..."
      Rails.logger.info "🎙️  Using model: whisper-1"

      # Whisper APIで音声を文字起こし
      response = client.audio.transcribe(
        parameters: {
          model: "whisper-1",
          file: File.open(temp_file.path, "rb"),
          response_format: "json"
        }
      )
      Rails.logger.info "📥 Whisper API response received successfully"
      Rails.logger.info "📝 Response keys: #{response.keys.join(', ')}" if response.is_a?(Hash)

      transcribed_text = response["text"]
      Rails.logger.info "Transcribed text: #{transcribed_text&.length || 0} characters"

      # メモリ解放（大きなファイル処理後）
      response = nil
      GC.start
      Rails.logger.info "🧹 Memory cleanup after Whisper API call"

      if transcribed_text.present?
        Rails.logger.info "Starting GPT formatting for transcribed text..."

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
              prompt_type: "voice_transcription",
              organization_id: nil
            )
          end
        else
          # プロンプトテンプレートが指定されていない場合はデフォルトを使用
          Rails.logger.info "No custom prompt template selected, using default"
          prompt_template = PromptTemplate.find_template(
            meeting_type: meeting_type,
            prompt_type: "voice_transcription",
            organization_id: nil
          )
        end

        Rails.logger.info "Using prompt template: #{prompt_template.name}"
        Rails.logger.info "System prompt length: #{prompt_template.system_prompt.length} chars"
        Rails.logger.info "User prompt template length: #{prompt_template.user_prompt_template.length} chars"

        # 文字起こしされたテキストを議事録形式に整形
        Rails.logger.info "📝 Transcribed text length: #{transcribed_text.length} characters"
        Rails.logger.info "📝 First 200 chars of transcribed text: #{transcribed_text[0...200]}..."

        formatted_response = client.chat(
          parameters: {
            model: "gpt-4o-mini",
            messages: [
              {
                role: "system",
                content: prompt_template.system_prompt
              },
              {
                role: "user",
                content: prompt_template.generate_user_prompt(transcribed_text: transcribed_text)
              }
            ],
            max_tokens: 4000,  # 音声内容を充実させるため大幅に増量
            temperature: 0.5   # 自然さを向上
          }
        )
        Rails.logger.info "GPT formatting completed with custom prompt template"

        formatted_text = formatted_response.dig("choices", 0, "message", "content") || transcribed_text

        # メモリ解放（GPT処理後）
        formatted_response = nil
        transcribed_text = nil
        GC.start
        Rails.logger.info "🧹 Memory cleanup after GPT formatting"

        Rails.logger.info "Meeting voice transcription completed successfully"

        # WebSocket経由でフロントエンドに結果を送信
        # セッションIDがある場合（新規）とない場合（編集）で分岐
        if session_id.present?
          broadcast_channel = "ai_processing_session_#{session_id}"
          ActionCable.server.broadcast(
            broadcast_channel,
            {
              type: "meeting_voice_transcription",
              status: "completed",
              content: formatted_text
            }
          )
          Rails.logger.info "[ActionCable] Broadcasting to #{broadcast_channel}"

          # セッション用の一時データ保存（新規作成時）
          Rails.cache.write("temp_meeting_voice_transcription_#{session_id}", formatted_text, expires_in: 1.hour)
        else
          broadcast_channel = "ai_processing_#{meeting_id}"
          ActionCable.server.broadcast(
            broadcast_channel,
            {
              type: "meeting_voice_transcription",
              status: "completed",
              content: formatted_text
            }
          )
          Rails.logger.info "[ActionCable] Broadcasting to #{broadcast_channel}"
        end
      else
        raise "音声からの議事録生成に失敗しました"
      end

    rescue => e
      Rails.logger.error "会議音声認識エラー: #{e.message}"
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
          type: "meeting_voice_transcription",
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
    end
  end
end
