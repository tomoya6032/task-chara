class ActivitiesController < ApplicationController
  before_action :set_character

  def index
    @activities = @character.activities.order(created_at: :desc).limit(50)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def new
    @activity = @character.activities.build
    # AIチャットの会話履歴を取得
    @ai_conversations = get_ai_conversations
    # チャット内容をプリセット用にセット（パラメーターで指定されている場合）
    if params[:from_chat].present?
      @activity.content = params[:content] if params[:content].present?
    end

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def create
    @activity = @character.activities.build(activity_params)

    respond_to do |format|
      if @activity.save
        format.turbo_stream {
          render turbo_stream: [
            turbo_stream.update("character-display",
              partial: "dashboards/character_display",
              locals: { character: @character.reload }
            ),
            turbo_stream.update("status-bars",
              partial: "shared/status_bars",
              locals: { character: @character }
            ),
            turbo_stream.replace("activity_form_modal", ""),
            turbo_stream.append("flash-container",
              partial: "shared/success_modal",
              locals: {
                title: "投稿完了！",
                message: "日報を投稿しました！\n✨ AIが解析中です...",
                redirect_url: activities_path,
                redirect_delay: 2000
              }
            )
          ]
        }
        format.html { redirect_to activities_path, notice: "日報を投稿しました！" }
      else
        format.turbo_stream { render :new, status: :unprocessable_entity }
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def show
    @activity = @character.activities.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to activities_path, alert: "指定された日報が見つかりません。"
  end

  def edit
    @activity = @character.activities.find(params[:id])

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to activities_path, alert: "指定された日報が見つかりません。"
  end

  def update
    @activity = @character.activities.find(params[:id])

    if @activity.update(activity_params)
      redirect_to activity_path(@activity), notice: "日報を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to activities_path, alert: "指定された日報が見つかりません。"
  end

  def destroy
    @activity = @character.activities.find(params[:id])
    @activity.destroy

    redirect_to activities_path, notice: "日報を削除しました。"
  rescue ActiveRecord::RecordNotFound
    redirect_to activities_path, alert: "指定された日報が見つかりません。"
  end

  # 画像OCR処理の開始
  def process_image_ocr
    # 新規作成時と既存編集時の対応
    if params[:id] == 'new'
      # 新規作成時は固定IDを使用（フロントエンドと一致させる）
      activity_id = "new"
    else
      @activity = @character.activities.find(params[:id])
      activity_id = @activity.id
    end
    
    Rails.logger.info "=== OCR Process Started ==="
    Rails.logger.info "Activity ID: #{activity_id}"
    Rails.logger.info "Original ID param: #{params[:id]}"
    
    if params[:image_file].present?
      image_file = params[:image_file]
      Rails.logger.info "Image file received: #{image_file.original_filename}"
      
      # 一時ファイルに画像を保存
      temp_file = Tempfile.new(['ocr_image', File.extname(image_file.original_filename)])
      temp_file.binmode
      temp_file.write(image_file.read)
      temp_file.close
      
      Rails.logger.info "Temp file created: #{temp_file.path}"
      
      # バックグラウンドジョブを開始
      ProcessImageOcrJob.perform_later(activity_id, temp_file.path)
      Rails.logger.info "Background job queued for activity_id: #{activity_id}"
      
      render json: { 
        status: 'processing',
        message: '画像から文字起こし中です...',
        activity_id: temp_id
      }
    else
      render json: { 
        status: 'error',
        message: '画像ファイルがありません'
      }, status: :bad_request
    end
  rescue => e
    Rails.logger.error "Image OCR Error: #{e.message}"
    render json: { 
      status: 'error',
      message: "エラーが発生しました: #{e.message}"
    }, status: :internal_server_error
  end

  # 音声アップロードと文字起こし処理
  def process_voice_transcription
    # 新規作成時と既存編集時の対応
    if params[:id] == 'new'
      # 新規作成時は固定IDを使用（フロントエンドと一致させる）
      activity_id = "new"
    else
      @activity = @character.activities.find(params[:id])
      activity_id = @activity.id
    end
    
    Rails.logger.info "=== Voice Process Started ==="
    Rails.logger.info "Activity ID: #{activity_id}"
    
    if params[:audio_file].present?
      audio_file = params[:audio_file]
      Rails.logger.info "Audio file received: #{audio_file.original_filename}"
      
      # 一時ファイルに音声を保存
      temp_file = Tempfile.new(['voice_transcription', File.extname(audio_file.original_filename)])
      temp_file.binmode
      temp_file.write(audio_file.read)
      temp_file.close
      
      # バックグラウンドジョブを開始
      ProcessVoiceTranscriptionJob.perform_later(activity_id, temp_file.path)
      Rails.logger.info "Voice job queued for activity_id: #{activity_id}"
      
      render json: { 
        status: 'processing',
        message: '音声から文字起こし中です...',
        activity_id: activity_id
      }
    else
      render json: { 
        status: 'error',
        message: '音声ファイルがありません'
      }, status: :bad_request
    end
  rescue => e
    Rails.logger.error "Voice Transcription Error: #{e.message}"
    render json: { 
      status: 'error',
      message: "エラーが発生しました: #{e.message}"
    }, status: :internal_server_error
  end

  # AIチャット情報から日報を生成
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

      # AIを使って日報を生成
      generated_content = generate_daily_report_from_chat(conversation_history)
      
      render json: {
        success: true,
        content: generated_content,
        message: "AIチャット情報から日報を生成しました"
      }

    rescue => e
      Rails.logger.error "Chat to daily report generation error: #{e.message}"
      render json: { 
        error: "日報生成に失敗しました: #{e.message}" 
      }, status: :internal_server_error
    end
  end

  private

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

  def activity_params
    params.require(:activity).permit(:title, :content, :image, :image_url, :category, :mood_level, :fatigue_level, :visit_start_time, :visit_end_time)
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
  
  # AIチャット履歴から日報を生成
  def generate_daily_report_from_chat(conversation_history)
    client = OpenAI::Client.new
    
    # チャット履歴をテキストに整形
    chat_context = conversation_history.map do |msg|
      role_label = msg[:role] == 'user' ? 'ユーザー' : 'AI秘書'
      "#{role_label}: #{msg[:content]}"
    end.join("\n\n")
    
    # 日報生成用プロンプト
    system_prompt = build_daily_report_generation_prompt
    
    messages = [
      { role: "system", content: system_prompt },
      { role: "user", content: "以下のAI秘書との会話履歴を基に日報を作成してください：\n\n#{chat_context}" }
    ]
    
    response = client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: messages,
        max_tokens: 2000,
        temperature: 0.3
      }
    )
    
    response.dig("choices", 0, "message", "content") || "日報の生成に失敗しました。"
  end
  
  # 日報生成用システムプロンプト
  def build_daily_report_generation_prompt
    current_date = Time.current.strftime("%Y年%m月%d日")
    <<~PROMPT
      あなたは日報作成の専門家です。AI秘書との会話履歴から、業務や活動に関連する情報を抽出し、適切な日報形式で整理してください。
      
      【日報の構成】
      1. 日付・基本情報
         - 日付: #{current_date}
         - 作業時間/勤務状況
         
      2. 実施した業務・活動内容
         - 主な業務
         - 実施した活動
         - 取り組んだタスク
         
      3. 成果・進捗状況
         - 達成したこと
         - 進捗した項目
         - 完了したタスク
         
      4. 問題点・課題
         - 発生した問題
         - 未解決の課題
         - 改善が必要な点
         
      5. 明日の予定・目標
         - 予定している業務
         - 目標や重点項目
         - 準備が必要なこと
         
      6. その他・連絡事項
         - 特記事項
         - 連絡・共有事項
         - 気づきや提案
      
      【注意事項】
      - 会話の文脈から業務性質を推測し、適切な日報として整理してください
      - 個人情報や機密性の高い内容は適切に匿名化してください
      - 会話にない情報は推測せず、「（詳細は要確認）」等の注釈を入れてください
      - 業務的で実用的な日報として作成してください
    PROMPT
  end
  
  # テキスト切り詰め用ヘルパー
  def truncate_text(text, length)
    return "" if text.blank?
    text.length > length ? "#{text[0...length]}..." : text
  end
end
