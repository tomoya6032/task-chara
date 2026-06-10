class DashboardsController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :show ]
  skip_before_action :check_token_limit, only: [ :show ]

  def show
    if user_signed_in?
      # ログイン済みユーザーのダッシュボード
      @character = current_user.character
      @recent_activities = current_user.activities.recent.limit(5)
      @pending_tasks = current_user.tasks.pending.visible.limit(10)
      @upcoming_events = current_user.events.where("start_time >= ?", Time.current).order(:start_time).limit(5)
    else
      # 未ログインユーザー向けのデモ表示
      render :public_landing
    end
  end
end
