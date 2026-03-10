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
