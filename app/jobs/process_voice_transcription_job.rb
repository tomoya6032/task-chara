require "open3"
require "tmpdir"

class ProcessVoiceTranscriptionJob < ApplicationJob
  queue_as :default

  MAX_UPLOAD_BYTES = 50 * 1024 * 1024
  WHISPER_MAX_BYTES = 25 * 1024 * 1024
  SAFE_CHUNK_TARGET_BYTES = 24 * 1024 * 1024
  CHUNK_DURATION_SECONDS = 20 * 60
  CHUNK_AUDIO_BITRATE = "144k"
  CHUNK_AUDIO_SAMPLE_RATE = 16_000
  CHUNK_AUDIO_CHANNELS = 1
  FFMPEG_CANDIDATES = [
    ENV["FFMPEG_PATH"],
    ENV["FFMPEG_BINARY"],
    "/opt/homebrew/bin/ffmpeg",
    "/opt/homebrew/opt/ffmpeg/bin/ffmpeg",
    "/usr/local/bin/ffmpeg"
  ].compact.freeze

  def perform(activity_id, audio_file_path)
    Rails.logger.info "Starting voice transcription for activity_id: #{activity_id}"

    begin
      ensure_audio_file_exists!(audio_file_path)
      file_size = File.size(audio_file_path)
      Rails.logger.info "Audio file size: #{file_size} bytes (#{(file_size.to_f / 1024 / 1024).round(2)}MB)"

      if file_size > MAX_UPLOAD_BYTES
        raise "音声ファイルは50MB以下にしてください"
      end

      client = OpenAI::Client.new

      transcribed_text = transcribe_audio(client, activity_id, audio_file_path, file_size)

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
            type: "voice_transcription",
            status: "completed",
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
          type: "voice_transcription",
          status: "error",
          error: e.message
        }
      )
    ensure
      # 一時ファイルを削除
      File.delete(audio_file_path) if File.exist?(audio_file_path)
    end
  end

  private

  def ensure_audio_file_exists!(audio_file_path)
    raise "音声ファイルが見つかりません" unless File.exist?(audio_file_path)
  end

  def transcribe_audio(client, activity_id, audio_file_path, file_size)
    if file_size <= WHISPER_MAX_BYTES
      Rails.logger.info "Audio is within Whisper limit. Transcribing directly."
      broadcast_progress(activity_id, status: "processing", message: "音声を解析しています...", current: 1, total: 1, percent: 100)
      return transcribe_single_file(client, audio_file_path)
    end

    Rails.logger.info "Audio exceeds Whisper limit, splitting into chunks before transcription"
    transcribe_in_chunks(client, activity_id, audio_file_path)
  end

  def transcribe_single_file(client, audio_file_path)
    response = File.open(audio_file_path, "rb") do |file|
      client.audio.transcribe(
        parameters: {
          model: "whisper-1",
          file: file,
          response_format: "json"
        }
      )
    end

    response["text"].to_s
  end

  def transcribe_in_chunks(client, activity_id, audio_file_path)
    ffmpeg_binary = resolve_ffmpeg_binary
    unless ffmpeg_binary
      raise "50MBの音声を処理するにはffmpegが必要です（候補: #{FFMPEG_CANDIDATES.join(', ')}）"
    end

    Dir.mktmpdir("voice_transcription_chunks") do |dir|
      output_pattern = File.join(dir, "chunk_%03d.mp3")
      broadcast_progress(activity_id, status: "processing", message: "音声を分割しています...", current: 0, total: 0, percent: 0)
      split_audio_into_chunks(ffmpeg_binary, audio_file_path, output_pattern)

      chunk_files = Dir.glob(File.join(dir, "chunk_*.mp3")).sort_by do |path|
        File.basename(path)[/chunk_(\d+)\.mp3$/, 1].to_i
      end
      raise "音声を分割できませんでした" if chunk_files.empty?

      Rails.logger.info "Created #{chunk_files.length} audio chunks"

      total_chunks = chunk_files.length
      chunk_texts = chunk_files.each_with_index.map do |chunk_file, index|
        chunk_size_mb = (File.size(chunk_file).to_f / 1024 / 1024).round(2)
        Rails.logger.info "Transcribing chunk #{index + 1}/#{chunk_files.length} (#{chunk_size_mb}MB)"

        if File.size(chunk_file) > SAFE_CHUNK_TARGET_BYTES
          Rails.logger.warn "Chunk #{index + 1} exceeds safe target size: #{chunk_size_mb}MB"
        end

        transcribed_chunk = transcribe_single_file(client, chunk_file)

        broadcast_progress(
          activity_id,
          status: "processing",
          message: "チャンクを文字起こししています",
          current: index + 1,
          total: total_chunks,
          percent: (((index + 1).to_f / total_chunks) * 100).round
        )

        transcribed_chunk.present? ? transcribed_chunk : nil
      end.compact

      broadcast_progress(
        activity_id,
        status: "processing",
        message: "文字起こしテキストをまとめています",
        current: total_chunks,
        total: total_chunks,
        percent: 100
      )

      chunk_texts.join("\n\n")
    end
  end

  def split_audio_into_chunks(ffmpeg_binary, input_path, output_pattern)
    command = [
      ffmpeg_binary, "-y",
      "-i", input_path,
      "-vn",
      "-ac", CHUNK_AUDIO_CHANNELS.to_s,
      "-ar", CHUNK_AUDIO_SAMPLE_RATE.to_s,
      "-b:a", CHUNK_AUDIO_BITRATE,
      "-f", "segment",
      "-segment_time", CHUNK_DURATION_SECONDS.to_s,
      "-reset_timestamps", "1",
      output_pattern
    ]

    stdout, stderr, status = Open3.capture3(*command)
    return if status.success?

    raise "音声の分割に失敗しました: #{stderr.presence || stdout.presence || 'unknown error'}"
  end

  def resolve_ffmpeg_binary
    FFMPEG_CANDIDATES.each do |candidate|
      next if candidate.blank?

      return candidate if File.executable?(candidate)
    end

    "ffmpeg" if system("ffmpeg", "-version", out: File::NULL, err: File::NULL)
  end

  def broadcast_progress(activity_id, status:, message:, current:, total:, percent:)
    ActionCable.server.broadcast(
      "ai_processing_#{activity_id}",
      {
        type: "voice_transcription",
        status: status,
        phase: "transcribing",
        message: message,
        current_chunk: current,
        total_chunks: total,
        progress_percent: percent
      }
    )
  end
end
