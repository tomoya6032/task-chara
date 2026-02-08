class TasksController < ApplicationController
  before_action :set_character
  before_action :set_task, only: [ :show, :complete ]

  def new
    @task = @character.tasks.build
  end

  def create
    @task = @character.tasks.build(task_params)

    if @task.save
      render turbo_stream: [
        turbo_stream.append("tasks-list",
          partial: "tasks/task_item",
          locals: { task: @task }
        ),
        turbo_stream.replace("task-form-modal", ""),
        turbo_stream.append("flash-messages",
          partial: "shared/flash",
          locals: { message: "タスクを追加しました！", type: "success" }
        )
      ]
    else
      render :new, status: :unprocessable_entity
    end
  end

  def complete
    @task.mark_as_completed!

    render turbo_stream: [
      turbo_stream.update("task-#{@task.id}",
        partial: "tasks/task_item",
        locals: { task: @task.reload }
      ),
      turbo_stream.update("character-display",
        partial: "dashboards/character_display",
        locals: { character: @character.reload }
      ),
      turbo_stream.update("status-bars",
        partial: "dashboards/status_bars",
        locals: { character: @character }
      ),
      turbo_stream.append("flash-messages",
        partial: "shared/flash",
        locals: {
          message: "タスク完了！強靭さが向上しました！💪",
          type: "success"
        }
      )
    ]
  end

  def show
    # タスク詳細表示
  end

  private

  def set_character
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

  def set_task
    @task = @character.tasks.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:title, :category, :dislike_level)
  end
end
