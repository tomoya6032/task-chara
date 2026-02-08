class ActivitiesController < ApplicationController
  before_action :set_character

  def new
    @activity = @character.activities.build
  end

  def create
    @activity = @character.activities.build(activity_params)

    if @activity.save
      render turbo_stream: [
        turbo_stream.update("character-display",
          partial: "dashboards/character_display",
          locals: { character: @character.reload }
        ),
        turbo_stream.update("status-bars",
          partial: "dashboards/status_bars",
          locals: { character: @character }
        ),
        turbo_stream.replace("activity-form-modal", ""),
        turbo_stream.append("flash-messages",
          partial: "shared/flash",
          locals: { message: "日報を投稿し、AIが解析中です！✨", type: "success" }
        )
      ]
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @activity = Activity.find(params[:id])
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
    params.require(:activity).permit(:content, :image_url)
  end
end
