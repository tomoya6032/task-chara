class MeetingMinutesController < ApplicationController
  before_action :set_character
  before_action :set_meeting_minute, only: [ :show, :edit, :update, :destroy, :generate ]

  def index
    @meeting_minutes = @character.meeting_minutes.recent.page(params[:page]).per(10)
  end

  def show
  end

  def new
    @meeting_minute = @character.meeting_minutes.build
    # デフォルトで今日の日時を設定
    @meeting_minute.meeting_date = Time.current
    # プロンプトテンプレートのリストを取得
    @prompt_templates = PromptTemplate.active.order(:meeting_type, :prompt_type, :name)
    # AIチャットの会話履歴を取得
    @ai_conversations = get_ai_conversations
    # チャット内容をプリセット用にセット（パラメーターで指定されている場合）
    if params[:from_chat].present?
      @meeting_minute.content = params[:content] if params[:content].present?
    end
  end

  def create
    @meeting_minute = @character.meeting_minutes.build(meeting_minute_params)

    # セッションおよびキャッシュから音声・画像の解析結果を取得
    voice_content = session[:voice_transcription_temp].try(:[], :content) ||
                    Rails.cache.read("temp_meeting_voice_transcription_#{session.id}")
    image_content = session[:image_ocr_temp].try(:[], :content) ||
                    Rails.cache.read("temp_meeting_image_ocr_#{session.id}")

    # AI解析結果をcontentに統合
    if voice_content.present? || image_content.present?
      combined_content = []
      combined_content << "【音声から生成された議事録】\n#{voice_content}" if voice_content.present?
      combined_content << "【画像から生成された議事録】\n#{image_content}" if image_content.present?

      # 既存のcontentと結合
      if @meeting_minute.content.present?
        @meeting_minute.content = combined_content.join("\n\n") + "\n\n" + @meeting_minute.content
      else
        @meeting_minute.content = combined_content.join("\n\n")
      end

      # AI解析結果がある場合は完成状態に設定
      @meeting_minute.status = :completed
      Rails.logger.info "Meeting minute status set to completed due to AI-generated content"
    else
      # AI解析結果がない場合は下書き状態
      @meeting_minute.status = :draft
      Rails.logger.info "Meeting minute status set to draft (no AI content)"
    end

    if @meeting_minute.save
      # セッション一時データ＆キャッシュをクリア
      session.delete(:voice_transcription_temp)
      session.delete(:image_ocr_temp)
      Rails.cache.delete("temp_meeting_voice_transcription_#{session.id}")
      Rails.cache.delete("temp_meeting_image_ocr_#{session.id}")

      respond_to do |format|
        format.html { redirect_to meeting_minute_path(@meeting_minute), notice: "会議議事録を作成しました。" }
        format.turbo_stream {
          flash[:notice] = "会議議事録を作成しました。"
          redirect_to meeting_minute_path(@meeting_minute), status: :see_other
        }
      end
    else
      Rails.logger.warn "Meeting minute validation failed: #{@meeting_minute.errors.full_messages.join(', ')}"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # プロンプトテンプレートのリストを取得
    @prompt_templates = PromptTemplate.active.order(:meeting_type, :prompt_type, :name)
    # AIチャットの会話履歴を取得
    @ai_conversations = get_ai_conversations
  end

  def update
    if @meeting_minute.update(meeting_minute_params)
      respond_to do |format|
        format.html { redirect_to meeting_minute_path(@meeting_minute), notice: "会議議事録を更新しました。" }
        format.turbo_stream {
          flash[:notice] = "会議議事録を更新しました。"
          redirect_to meeting_minute_path(@meeting_minute), status: :see_other
        }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @meeting_minute.destroy
    redirect_to meeting_minutes_path, notice: "会議議事録を削除しました。"
  end

  def generate
    if @meeting_minute.draft? || @meeting_minute.error?
      GenerateMeetingMinutesJob.perform_later(@meeting_minute)
      redirect_to meeting_minute_path(@meeting_minute), notice: "議事録の生成を開始しました。"
    else
      redirect_to meeting_minute_path(@meeting_minute), alert: "現在生成中または既に完成しています。"
    end
  end

  # 画像OCR処理の開始（新規作成用）
  def process_image_ocr_new
    Rails.logger.info "=== Image OCR Request Started ==="
    Rails.logger.info "Params keys: #{params.keys}"
    Rails.logger.info "Rails Session ID: #{session.id}"
    Rails.logger.info "JS Session ID param: #{params[:session_id]}"

    if params[:image_file].present?
      image_file = params[:image_file]
      Rails.logger.info "Image file received for new meeting: #{image_file.original_filename}"

      # JSから送られてきたsession_idを優先、なければRails session.idを使用
      used_session_id = params[:session_id] || session.id.to_s
      Rails.logger.info "📋 Using session ID: #{used_session_id} (source: #{params[:session_id] ? 'JS param' : 'Rails session'})"

      # セッションに画像ファイル情報を保存
      session[:image_ocr_temp] = {
        filename: image_file.original_filename,
        content_type: image_file.content_type
      }

      # 一時ファイルに画像を保存
      temp_file = Tempfile.new([ "meeting_image_ocr", File.extname(image_file.original_filename) ])
      temp_file.binmode
      temp_file.write(image_file.read)
      temp_file.close

      # プロンプトテンプレートIDを取得
      prompt_template_id = params[:prompt_template_id]
      Rails.logger.info "📝 Prompt template ID: #{prompt_template_id || 'Not specified (will use default)'}"

      # バックグラウンドジョブを開始（session_idをJob第一引数に渡す）
      Rails.logger.info "🚀 Queuing ProcessMeetingImageOcrJob..."
      Rails.logger.info "📤 Job arguments: session_#{used_session_id}, #{temp_file.path}, #{prompt_template_id}"
      ProcessMeetingImageOcrJob.perform_later("session_#{used_session_id}", temp_file.path, prompt_template_id)
      Rails.logger.info "✅ Meeting OCR job queued for session: #{used_session_id}"

      render json: {
        status: "processing",
        message: "画像から議事録テキストを生成中です...",
        session_id: used_session_id
      }
    else
      render json: {
        status: "error",
        message: "画像ファイルが見つかりません"
      }
    end
  end

  # 画像OCR処理の開始
  def process_image_ocr
    meeting_id = params[:meeting_id] || params[:id]

    if params[:image_file].present?
      image_file = params[:image_file]
      Rails.logger.info "Image file received: #{image_file.original_filename}"

      # プロンプトテンプレートIDを取得
      prompt_template_id = params[:prompt_template_id]
      Rails.logger.info "📝 Prompt template ID: #{prompt_template_id || 'Not specified (will use default)'}"

      # 一時ファイルに画像を保存
      temp_file = Tempfile.new([ "meeting_image_ocr", File.extname(image_file.original_filename) ])
      temp_file.binmode
      temp_file.write(image_file.read)
      temp_file.close

      # バックグラウンドジョブを開始
      ProcessMeetingImageOcrJob.perform_later(meeting_id, temp_file.path, prompt_template_id)
      Rails.logger.info "Meeting OCR job queued for meeting_id: #{meeting_id}"

      render json: {
        status: "processing",
        message: "画像から議事録テキストを生成中です...",
        meeting_id: meeting_id
      }
    else
      render json: {
        status: "error",
        message: "画像ファイルが見つかりません"
      }
    end
  end

  # 音声アップロードと文字起こし処理（新規作成用）
  def process_voice_transcription_new
    Rails.logger.info "=== Voice Transcription Request Started ==="
    Rails.logger.info "Params keys: #{params.keys}"
    Rails.logger.info "Rails Session ID: #{session.id}"
    Rails.logger.info "JS Session ID param: #{params[:session_id]}"

    if params[:voice_file].present?
      voice_file = params[:voice_file]
      Rails.logger.info "✅ Voice file received for new meeting:"
      Rails.logger.info "  - Filename: #{voice_file.original_filename}"
      Rails.logger.info "  - Content Type: #{voice_file.content_type}"
      Rails.logger.info "  - Size: #{voice_file.size} bytes (#{(voice_file.size.to_f / 1024 / 1024).round(2)}MB)"

      # M4Aファイル特有のログ
      if voice_file.original_filename.downcase.end_with?(".m4a")
        Rails.logger.info "🎵 M4A file detected - iPhone/iOS recording format"
      end

      # JSから送られてきたsession_idを優先、なければRails session.idを使用
      used_session_id = params[:session_id] || session.id.to_s
      Rails.logger.info "📋 Using session ID: #{used_session_id} (source: #{params[:session_id] ? 'JS param' : 'Rails session'})"

      # セッションに音声ファイル情報を保存
      session[:voice_transcription_temp] = {
        filename: voice_file.original_filename,
        content_type: voice_file.content_type,
        size: voice_file.size,
        received_at: Time.current
      }

      # 一時ファイルに音声を保存
      file_extension = File.extname(voice_file.original_filename)
      temp_file = Tempfile.new([ "meeting_voice_transcription", file_extension ])
      temp_file.binmode

      Rails.logger.info "📁 Creating temporary file: #{temp_file.path}"
      temp_file.write(voice_file.read)
      temp_file.close

      Rails.logger.info "💾 Temporary file saved successfully"
      Rails.logger.info "  - Path: #{temp_file.path}"
      Rails.logger.info "  - Size: #{File.size(temp_file.path)} bytes"
      Rails.logger.info "  - Exists: #{File.exist?(temp_file.path)}"

      # プロンプトテンプレートIDを取得
      prompt_template_id = params[:prompt_template_id]
      Rails.logger.info "📝 Prompt template ID: #{prompt_template_id || 'Not specified (will use default)'}"

      # バックグラウンドジョブを開始（session_idをJob第一引数に渡す）
      Rails.logger.info "🚀 Queuing ProcessMeetingVoiceTranscriptionJob..."
      Rails.logger.info "📤 Job arguments: session_#{used_session_id}, #{temp_file.path}, #{prompt_template_id}"
      ProcessMeetingVoiceTranscriptionJob.perform_later("session_#{used_session_id}", temp_file.path, prompt_template_id)
      Rails.logger.info "✅ Meeting voice job queued for session: #{used_session_id}"

      render json: {
        status: "processing",
        message: "音声から議事録テキストを生成中です...",
        session_id: used_session_id,
        file_info: {
          name: voice_file.original_filename,
          size: voice_file.size,
          type: voice_file.content_type
        }
      }
    else
      Rails.logger.error "❌ No voice file found in request"
      Rails.logger.error "Available params: #{params.keys.join(', ')}"

      render json: {
        status: "error",
        message: "音声ファイルが見つかりません"
      }
    end
  end

  # 音声アップロードと文字起こし処理
  def process_voice_transcription
    meeting_id = params[:meeting_id] || params[:id]

    if params[:voice_file].present?
      voice_file = params[:voice_file]
      Rails.logger.info "Voice file received: #{voice_file.original_filename}"

      # プロンプトテンプレートIDを取得
      prompt_template_id = params[:prompt_template_id]
      Rails.logger.info "📝 Prompt template ID: #{prompt_template_id || 'Not specified (will use default)'}"

      # 一時ファイルに音声を保存
      temp_file = Tempfile.new([ "meeting_voice_transcription", File.extname(voice_file.original_filename) ])
      temp_file.binmode
      temp_file.write(voice_file.read)
      temp_file.close

      # バックグラウンドジョブを開始
      ProcessMeetingVoiceTranscriptionJob.perform_later(meeting_id, temp_file.path, prompt_template_id)
      Rails.logger.info "Meeting voice job queued for meeting_id: #{meeting_id}"

      render json: {
        status: "processing",
        message: "音声から議事録テキストを生成中です...",
        meeting_id: meeting_id
      }
    else
      render json: {
        status: "error",
        message: "音声ファイルが見つかりません"
      }
    end
  end

  # AIチャット情報から議事録を生成
  def generate_from_chat
    conversation_id = params[:conversation_id]
    if conversation_id.blank?
      render json: { error: "会話IDが指定されていません" }, status: :bad_request
      return
    end

    begin
      # 会話履歴を取得
      conversation_history = AiChat.conversation_context(conversation_id, limit: 50)
      
      if conversation_history.empty?
        render json: { error: "指定された会話が見つかりません" }, status: :not_found
        return
      end

      # AIを使って議事録を生成
      generated_content = generate_meeting_minutes_from_chat(conversation_history)
      
      render json: {
        success: true,
        content: generated_content,
        message: "AIチャット情報から議事録を生成しました"
      }

    rescue => e
      Rails.logger.error "Chat to meeting minutes generation error: #{e.message}"
      render json: { 
        error: "議事録生成に失敗しました: #{e.message}" 
      }, status: :internal_server_error
    end
  end

  private

  def current_user
    # デモ用: 現在は固定のユーザーを使用
    @user
  end

  def set_character
    # デモ用: 現在は固定のキャラクターを使用
    @organization = Organization.find_or_create_by(name: "サンプル企業")
    @user = @organization.users.find_or_create_by(email: "demo@example.com")
    @character = @user.character || @user.create_character(
      name: "デモキャラクター",
      shave_level: 20,
      body_shape: 30,
      inner_peace: 40,
      intelligence: 50,
      toughness: 35
    )
  end

  def set_meeting_minute
    @meeting_minute = @character.meeting_minutes.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to meeting_minutes_path, alert: "指定された会議議事録が見つかりません。"
  end

  def meeting_minute_params
    params.require(:meeting_minute).permit(:title, :meeting_type, :meeting_date, :content, :participants, :location, :prompt_template_id)
  end

  # AIチャットの会話履歴を取得
  def get_ai_conversations
    # 最近の会話の一意な conversation_id を取得
    conversation_ids = AiChat.where(character: @character)
                             .select(:conversation_id)
                             .distinct
                             .order('MIN(created_at) DESC')
                             .group(:conversation_id)
                             .limit(10)
                             .pluck(:conversation_id)
    
    # 各会話の詳細情報を取得
    conversations = conversation_ids.map do |conv_id|
      messages = AiChat.for_conversation(conv_id).recent.limit(5)
      next if messages.empty?
      
      {
        conversation_id: conv_id,
        created_at: messages.last.created_at,
        preview: truncate_text(messages.first.content, 100),
        message_count: AiChat.for_conversation(conv_id).count,
        last_message_at: messages.first.created_at
      }
    end.compact.sort_by { |conv| conv[:last_message_at] }.reverse
    
    conversations
  end
  
  # AIチャット履歴から議事録を生成
  def generate_meeting_minutes_from_chat(conversation_history)
    client = OpenAI::Client.new
    
    # チャット履歴をテキストに整形
    chat_context = conversation_history.map do |msg|
      role_label = msg[:role] == 'user' ? 'ユーザー' : 'AI秘書'
      "#{role_label}: #{msg[:content]}"
    end.join("\n\n")
    
    # 議事録生成用プロンプト
    system_prompt = build_meeting_minutes_generation_prompt
    
    messages = [
      { role: "system", content: system_prompt },
      { role: "user", content: "以下のAI秘書との会話履歴を基に議事録を作成してください：\n\n#{chat_context}" }
    ]
    
    response = client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: messages,
        max_tokens: 2000,
        temperature: 0.3
      }
    )
    
    response.dig("choices", 0, "message", "content") || "議事録の生成に失敗しました。"
  end
  
  # 議事録生成用システムプロンプト
  def build_meeting_minutes_generation_prompt
    <<~PROMPT
      あなたは会議議事録作成の専門家です。AI秘書との会話履歴から、会議または打ち合わせに関連する情報を抽出し、適切な議事録形式で整理してください。
      
      【議事録の構成】
      1. 会議概要
         - 会議名/打ち合わせの目的
         - 日時（推定可能な場合）
         - 参加者（会話から推測）
         
      2. 議題・検討事項
         - 主要な話題
         - 検討された課題
         
      3. 主な内容・発言
         - 重要なポイント
         - 意見や提案
         
      4. 決定事項・合意内容
         - 決まったこと
         - 合意された内容
         
      5. 今後のアクション・課題
         - 次に行うべきこと
         - 持ち越し課題
         
      6. その他
         - 補足事項
         - 参考情報
      
      【注意事項】
      - 会話の文脈から会議の性質を推測し、適切な議事録として整理してください
      - 個人情報や機密性の高い内容は適切に匿名化してください
      - 会話にない情報は推測せず、「（詳細は要確認）」等の注釈を入れてください
      - 読みやすく、実用的な議事録として作成してください
    PROMPT
  end
  
  # テキスト切り詰め用ヘルパー
  def truncate_text(text, length)
    return "" if text.blank?
    text.length > length ? "#{text[0...length]}..." : text
  end
end
