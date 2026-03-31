class ProcessMeetingVoiceTranscriptionJob < ApplicationJob
  queue_as :default

  def perform(meeting_id_or_session, audio_file_path, prompt_template_id = nil)
    Rails.logger.info "🤖 === Starting Meeting Voice Transcription Job ==="
    Rails.logger.info "📋 Meeting ID or Session: #{meeting_id_or_session}"
    Rails.logger.info "📁 Audio file path: #{audio_file_path}"
    Rails.logger.info "📝 Custom prompt template ID: #{prompt_template_id || 'Not specified'}"
    Rails.logger.info "✅ Audio file exists: #{File.exist?(audio_file_path)}"

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

    if File.exist?(audio_file_path)
      file_size = File.size(audio_file_path)
      file_extension = File.extname(audio_file_path).downcase
      Rails.logger.info "📊 File details:"
      Rails.logger.info "  - Size: #{file_size} bytes (#{(file_size.to_f / 1024 / 1024).round(2)}MB)"
      Rails.logger.info "  - Extension: #{file_extension}"

      # M4Aファイルの特別な処理ログ
      if file_extension == ".m4a"
        Rails.logger.info "🎵 Processing M4A file (iPhone/iOS format)"
      end
    else
      Rails.logger.error "❌ Audio file not found at path: #{audio_file_path}"
      return
    end

    begin
      # 他のセクションと同じ方法で OpenAI クライアントを作成
      client = OpenAI::Client.new
      Rails.logger.info "🔗 OpenAI client initialized successfully"

      Rails.logger.info "📤 Sending audio file to OpenAI Whisper API..."
      Rails.logger.info "🎙️  Using model: whisper-1"

      # Whisper APIで音声を文字起こし
      response = client.audio.transcribe(
        parameters: {
          model: "whisper-1",
          file: File.open(audio_file_path, "rb"),
          response_format: "json"
        }
      )
      Rails.logger.info "📥 Whisper API response received successfully"
      Rails.logger.info "📝 Response keys: #{response.keys.join(', ')}" if response.is_a?(Hash)

      transcribed_text = response["text"]
      Rails.logger.info "Transcribed text: #{transcribed_text&.length || 0} characters"

      if transcribed_text.present?
        Rails.logger.info "Starting GPT formatting for transcribed text..."

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
      # 一時ファイルを削除
      File.delete(audio_file_path) if File.exist?(audio_file_path)
    end
  end
end
