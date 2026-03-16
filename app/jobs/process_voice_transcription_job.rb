class ProcessVoiceTranscriptionJob < ApplicationJob
  queue_as :default

  def perform(activity_id, audio_file_path)
    Rails.logger.info "Starting voice transcription for activity_id: #{activity_id}"
    
    begin
      client = OpenAI::Client.new
      
      # Whisper APIで音声を文字起こし
      response = client.audio.transcribe(
        parameters: {
          model: "whisper-1",
          file: File.open(audio_file_path, 'rb'),
          response_format: "json"
        }
      )
      
      transcribed_text = response["text"]
      
      if transcribed_text.present?
        # 文字起こしされたテキストを日報らしい形に整形
        formatted_response = client.chat(
          parameters: {
            model: "gpt-4o-mini", # より効率的なモデルに変更
            messages: [
              {
                role: "system",
                content: "あなたは業務報告書作成のアシスタントです。音声から文字起こしされた内容を、適切な報告書の形式に整理・要約してください。個人情報や機密情報に該当する可能性のある固有名詞は一般的な表現に置き換えて、プライバシーに配慮してください。"
              },
              {
                role: "user",
                content: "以下の音声内容を業務報告書として適切に整理してください。以下の観点で構成してください：

1. 業務活動の概要（訪問・面談・会議など）
2. 相談内容や議題の要点（要約形式）
3. 実施した支援や対応の概要
4. 気づいた点や今後の課題
5. その他特筆すべき事項

音声内容：
#{transcribed_text}"
              }
            ],
            max_tokens: 800, # トークン数を増やして詳細な報告書を生成
            temperature: 0.3 # 報告書らしい表現のために創造性を少し上げる
          }
        )
        
        formatted_text = formatted_response.dig("choices", 0, "message", "content") || transcribed_text
        
        Rails.logger.info "Voice transcription completed successfully"
        
        # WebSocket経由でフロントエンドに結果を送信
        ActionCable.server.broadcast(
          "ai_processing_#{activity_id}",
          {
            type: 'voice_transcription',
            status: 'completed',
            content: formatted_text
          }
        )
      else
        raise "音声の文字起こしに失敗しました"
      end
      
    rescue => e
      Rails.logger.error "音声認識エラー: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      ActionCable.server.broadcast(
        "ai_processing_#{activity_id}",
        {
          type: 'voice_transcription',
          status: 'error',
          error: e.message
        }
      )
    ensure
      # 一時ファイルを削除
      File.delete(audio_file_path) if File.exist?(audio_file_path)
    end
  end
end