class TasksController < ApplicationController
  before_action :set_character
  before_action :set_task, only: [ :show, :edit, :update, :notify_line, :complete, :hide, :unhide, :approve, :destroy ]

  def index
    sort_by = params[:sort] || "created_date"

    @tasks = case sort_by
    when "due_date"
               @character.tasks.includes(:character).ordered_by_due_date
    else
               @character.tasks.includes(:character).ordered_by_created_date
    end

    @pending_tasks = @tasks.pending.published
    @completed_tasks = @tasks.completed.published
    @hidden_tasks = @tasks.where(hidden: true).published
    @draft_tasks = @character.tasks.draft.includes(:extracted_from_activity).ordered_by_created_date
    @current_sort = sort_by
    @task_categories = load_task_categories
  end

  def completed
    @completed_tasks = @character.tasks.completed.order(completed_at: :desc)
  end

  def new
    @task = @character.tasks.build
    @task_categories = load_task_categories

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
    respond_to do |format|
      format.html { redirect_to tasks_path }
      format.json { render json: @task }
    end
  end

  def edit
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def update
    if @task.update(task_params)
      respond_to do |format|
        format.html do
          redirect_to tasks_path, notice: "✅ タスク「#{@task.title}」を更新しました！"
        end
        format.json { render json: { success: true, task: @task } }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @task.errors } }
      end
    end
  end

  def notify_line
    user = @character&.user

    if user.nil? || user.line_user_id.blank?
      respond_to do |format|
        format.html { redirect_to tasks_path, alert: "LINE連携されていないため通知できません。" }
        format.json { render json: { success: false, error: "LINE連携されていないため通知できません。" }, status: :unprocessable_entity }
      end
      return
    end

    due_text = @task.due_date.present? ? @task.due_date.strftime("%m月%d日 %H:%M") : "期限なし"
    message = <<~TEXT.strip
      📋 タスクの通知
      件名: #{@task.title}
      期限: #{due_text}
      カテゴリ: #{@task.category_display}
      内容: #{@task.description.present? ? @task.description : "(説明なし)"}
    TEXT

    success = ::LineBotService.new.send_message(user.line_user_id, message)

    respond_to do |format|
      if success
        format.html { redirect_to tasks_path, notice: "LINEへタスク通知を送信しました。" }
        format.json { render json: { success: true, message: "LINEへタスク通知を送信しました。" }, status: :ok }
      else
        format.html { redirect_to tasks_path, alert: "LINE通知の送信に失敗しました。" }
        format.json { render json: { success: false, error: "LINE通知の送信に失敗しました。" }, status: :unprocessable_entity }
      end
    end
  rescue LoadError => e
    Rails.logger.error("[Tasks#notify_line] LoadError: #{e.class} - #{e.message}")
    respond_to do |format|
      format.html { redirect_to tasks_path, alert: "LINEライブラリの読み込みに失敗しました。" }
      format.json { render json: { success: false, error: "LINEライブラリの読み込みに失敗しました。", details: e.message }, status: :internal_server_error }
    end
  rescue NameError => e
    Rails.logger.error("[Tasks#notify_line] NameError: #{e.class} - #{e.message}")
    respond_to do |format|
      format.html { redirect_to tasks_path, alert: "LINE通知中に定数エラーが発生しました。" }
      format.json { render json: { success: false, error: "LINE通知中に定数エラーが発生しました。", details: e.message }, status: :internal_server_error }
    end
  rescue StandardError => e
    Rails.logger.error("[Tasks#notify_line] Error: #{e.class} - #{e.message}")
    respond_to do |format|
      format.html { redirect_to tasks_path, alert: "LINE通知の処理中にエラーが発生しました。" }
      format.json { render json: { success: false, error: "LINE通知の処理中にエラーが発生しました。", details: e.message }, status: :internal_server_error }
    end
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

  def approve
    if @task.draft?
      @task.approve!

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove("draft-task-#{@task.id}"),
            turbo_stream.prepend("published-tasks",
              render_to_string(partial: "tasks/task_card", locals: { task: @task, show_approve_button: false })
            ),
            turbo_stream.update("flash-messages",
              render_to_string(partial: "shared/flash_message", locals: { message: "タスクを承認しました", type: "success" })
            )
          ]
        end
        format.html { redirect_to tasks_path, notice: "タスク「#{@task.title}」を承認しました" }
        format.json { render json: { status: "approved", task_id: @task.id, message: "タスクを承認しました" } }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash-messages",
            render_to_string(partial: "shared/flash_message", locals: { message: "このタスクは承認できません", type: "error" })
          )
        end
        format.html { redirect_to tasks_path, alert: "このタスクは承認できません" }
        format.json { render json: { error: "Cannot approve this task" }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    was_draft = @task.draft?
    task_title = @task.title
    @task.destroy!

    respond_to do |format|
      format.turbo_stream do
        if was_draft
          render turbo_stream: [
            turbo_stream.remove("draft-task-#{@task.id}"),
            turbo_stream.update("flash-messages",
              render_to_string(partial: "shared/flash_message", locals: { message: "「#{task_title}」を却下しました", type: "warning" })
            )
          ]
        else
          render turbo_stream: turbo_stream.remove("task-#{@task.id}")
        end
      end
      format.html do
        if was_draft
          redirect_to tasks_path, notice: "「#{task_title}」を却下しました"
        else
          redirect_to dashboard_path, notice: "タスクを完全に削除しました"
        end
      end
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

  def load_task_categories
    return default_task_categories unless @character&.calendar_settings.present?

    settings = @character.calendar_settings_hash
    cats = settings["custom_categories"]
    # インデックス付きハッシュ（ActionController::Parameters由来）を配列に変換
    cats = cats.values if cats.is_a?(Hash) && cats.keys.all? { |k| k.to_s =~ /^\d+$/ }
    return default_task_categories unless cats.is_a?(Array) && cats.any?

    cats.map { |c| [ c["name"], c["id"] ] }
  rescue StandardError
    default_task_categories
  end

  def default_task_categories
    [ [ "個人", "personal" ], [ "仕事", "work" ], [ "ミーティング", "meeting" ], [ "タスク期限", "task_deadline" ] ]
  end

  def task_params
    params.require(:task).permit(:title, :category, :dislike_level, :due_date, :description)
  end
end
