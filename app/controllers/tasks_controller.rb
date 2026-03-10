class TasksController < ApplicationController
  before_action :set_character
  before_action :set_task, only: [ :show, :complete, :hide, :unhide, :destroy ]

  def index
    sort_by = params[:sort] || "created_date"

    @tasks = case sort_by
    when "due_date"
               @character.tasks.includes(:character).ordered_by_due_date
    else
               @character.tasks.includes(:character).ordered_by_created_date
    end

    @pending_tasks = @tasks.pending
    @completed_tasks = @tasks.completed
    @hidden_tasks = @tasks.where(hidden: true)
    @current_sort = sort_by
  end

  def completed
    @completed_tasks = @character.tasks.completed.order(completed_at: :desc)
  end

  def new
    @task = @character.tasks.build

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def create
    @task = @character.tasks.build(task_params)
    @task.hidden = false if @task.hidden.nil?

    if @task.save
      respond_to do |format|
        format.turbo_stream do
          if params.dig(:task, :from_new_window) == "true"
            # 別ウィンドウからの場合：ウィンドウを閉じるJavaScriptを送信
            render turbo_stream: turbo_stream.update("task-modal",
              "<script>window.close();</script>")
          else
            # 通常のモーダルからの場合：既存のturbo_streamテンプレートを使用
            # デフォルトでcreate.turbo_stream.hamlが呼ばれる
          end
        end
        format.html do
          # すべての場合でダッシュボードにリダイレクト（シンプルな解決策）
          redirect_to dashboard_path, notice: "✅ タスク「#{@task.title}」を追加しました！"
        end
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
      format.html do
        toughness_gain = (@task.dislike_level || 1) * 1.5
        flash[:notice] = "🎉 お疲れさま！タスク「#{@task.title}」を完了しました！強靭さ+#{toughness_gain}pt獲得！"

        # リファラーに基づいてリダイレクト先を決定
        if request.referer&.include?("/tasks")
          redirect_to tasks_path
        else
          redirect_to dashboard_path
        end
      end
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

      respond_to do |format|
        format.html
        format.turbo_stream
      end
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
      format.html do
        flash[:notice] = "👁️ タスク「#{@task.title}」を非表示にしました"

        # リファラーに基づいてリダイレクト先を決定
        if request.referer&.include?("/tasks")
          redirect_to tasks_path
        else
          redirect_to dashboard_path
        end
      end
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
    params.require(:task).permit(:title, :category, :dislike_level, :due_date)
  end
end
