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
end
