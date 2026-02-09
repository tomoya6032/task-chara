class TasksController < ApplicationController
  before_action :set_character
  before_action :set_task, only: [ :show, :complete, :hide, :unhide, :destroy ]

  def new
    @task = @character.tasks.build
  end

  def create
    @task = @character.tasks.build(task_params)
    @task.hidden = false if @task.hidden.nil?

    if @task.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to dashboard_path, notice: "タスクが作成されました" }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :new, status: :unprocessable_entity }
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def complete
    @task.mark_as_completed!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("tasks-list",
            render_to_string(partial: "shared/tasks_overview", locals: { character: @character })
          ),
          turbo_stream.prepend("flash-container",
            render_to_string(partial: "shared/flash", locals: { message: "タスク完了！強靭さが向上しました！💪", type: "success" })
          )
        ]
      end
      format.html { redirect_to dashboard_path, notice: "タスクが完了しました" }
    end
  end

  def show
    # タスク詳細表示
  end

  def hidden
    begin
      unless @character
        render plain: "Character not found", status: 404
        return
      end

      # 直接クエリで安全にhiddenタスクを取得
      @hidden_tasks = Task.where(character: @character, hidden: true).order(updated_at: :desc)
    rescue => e
      Rails.logger.error "Error in hidden action: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      @hidden_tasks = []
      render plain: "Internal Server Error: #{e.message}", status: 500
      nil
    end
  end

  def hide
    @task.hide!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("task-#{@task.id}")
      end
      format.html { redirect_to dashboard_path, notice: "タスクを非表示にしました" }
    end
  end

  def unhide
    @task.unhide!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("hidden-task-#{@task.id}"),
          turbo_stream.replace("tasks-list",
            render_to_string(partial: "shared/tasks_overview", locals: { character: @character })
          )
        ]
      end
      format.html { redirect_to dashboard_path, notice: "タスクを復元しました" }
    end
  end

  def destroy
    @task.destroy!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("hidden-task-#{@task.id}")
      end
      format.html { redirect_to dashboard_path, notice: "タスクを完全に削除しました" }
    end
  end

  private

  def set_character
    begin
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
    rescue => e
      Rails.logger.error "Error setting character: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to root_path, alert: "キャラクター設定でエラーが発生しました"
    end
  end

  def set_task
    @task = @character.tasks.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:title, :category, :dislike_level)
  end
end
