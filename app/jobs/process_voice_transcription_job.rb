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
                content: "あなたは訪問介護・福祉現場の日報作成アシスタントです。音声から文字起こしされた内容を、親しみやすく分かりやすい自然な文章（丁寧語・ですます調）で日報として整理してください。マークダウン記号（#や##、-など）は一切使用せず、段落の頭に項目名を明記してください。大学生スタッフやチームメンバーが一読して状況が理解できるように、温かみのある表現で記述してください。個人情報や機密情報に該当する可能性のある固有名詞は一般的な表現に置き換えて、プライバシーに配慮してください。"
              },
              {
                role: "user",
                content: "以下の音声内容を日報として整理してください。必ず以下の4つの項目で構成し、全体の文字数は500〜800文字の範囲内（600文字程度が目安）に収めてください。マークダウン記号は一切使わず、項目名を段落の頭に明記してください。

【作成する日報の構成】

① 本日の訪問内容
録音データの概要を、大学生でも一読して状況が理解できるレベルに分かりやすく修正・要約して記載してください。

② 課題や修正点
訪問内容や対話から見えてきた課題、今後修正や確認が必要な点があれば、それらを具体的に書き残してください。特になければ「特になし」と記載してください。

③ 今後の方向性
今後の流れとして、次回の訪問時に行うこと、利用者様との約束ごと、次に発生するタスクを明確にし、チームや大学生スタッフに伝えるようにまとめてください。

④ その他
世間話をしている感じや、現場で談笑している雰囲気が伝わるように記述してください。また、利用者様の様子や、訪問したスタッフ自身の感情（嬉しかったこと、感じたこと、安心したことなど）が見えてくるように、温かみを持たせて書き残してください。

【音声転写内容】
#{transcribed_text}

上記の転写内容を基に、4つの項目すべてを含む日報を500〜800文字程度で作成してください。マークダウン記号は使わず、自然で温かみのある丁寧語で記述してください。"
              }
            ],
            max_tokens: 1200, # 文字数制限に対応するためトークン数を調整
            temperature: 0.5 # 温かみのある自然な表現のために適度な創造性を設定
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
