class TasksController < ApplicationController
  before_action :set_character
  before_action :set_task, only: [ :show, :edit, :update, :notify_line, :complete, :hide, :unhide, :approve, :destroy ]
  before_action :skip_head_requests, if: -> { request.head? }

  def index
    sort_by = params[:sort] || "created_date"

    # @characterを通じて取得するため、includes(:character)は不要
    @tasks = case sort_by
    when "due_date"
               @character.tasks.ordered_by_due_date
    else
               @character.tasks.ordered_by_created_date
    end

    @pending_tasks = @tasks.pending.published
    @completed_tasks = @tasks.completed.published
    @hidden_tasks = @tasks.where(hidden: true).published
    @draft_tasks = @character.tasks.draft.includes(:extracted_from_activity).ordered_by_created_date
    @current_sort = sort_by
    @task_categories = load_task_categories
  end

  def completed
    @completed_tasks = @character.tasks.completed.order(completed_at: :desc).limit(100)
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
    # デバッグログ: 認証状態とセッション情報を記録
    Rails.logger.info "🔍 TasksController#create called"
    Rails.logger.info "  - current_user: #{current_user.inspect}"
    Rails.logger.info "  - @character: #{@character.inspect}"
    Rails.logger.info "  - session.id: #{session.id.inspect}"
    Rails.logger.info "  - request.referer: #{request.referer}"
    
    # 二重送信防止チェック（セッションベース）
    request_token = generate_request_token
    if duplicate_request?(request_token)
      Rails.logger.warn "⚠️ Duplicate task creation attempt detected: #{request_token}"
      respond_to do |format|
        format.turbo_stream { head :no_content }
        format.html { 
          redirect_back_or_to(
            dashboard_path, 
            alert: "同じタスクを連続して作成することはできません。",
            status: :see_other
          ) 
        }
      end
      return
    end

    @task = @character.tasks.build(task_params)
    @task.hidden = false if @task.hidden.nil?

    if @task.save
      # 作成成功時にトークンを記録
      mark_request_processed(request_token)
      Rails.logger.info "✅ Task created successfully: #{@task.id} - #{@task.title}"
      Rails.logger.info "  - Response format: #{request.format}"
      Rails.logger.info "  - Will redirect to: #{request.referer&.include?('/tasks') ? tasks_path : dashboard_path}"

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
          # リダイレクト先を明示的に決定（root_pathへのリダイレクトを避ける）
          redirect_path = if request.referer&.include?("/tasks")
                           tasks_path
                         elsif request.referer&.include?("/dashboard")
                           dashboard_path
                         else
                           # リファラーが不明な場合はダッシュボードへ
                           dashboard_path
                         end
          
          Rails.logger.info "  - Final redirect path: #{redirect_path}"
          
          redirect_to redirect_path,
                     notice: "✅ タスク「#{@task.title}」を追加しました！",
                     status: :see_other
        end
      end
    else
      # バリデーションエラー時はトークンをクリア（再送信可能にする）
      clear_request_token(request_token)
      Rails.logger.warn "⚠️ Task validation failed: #{@task.errors.full_messages.join(', ')}"

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

        # リファラーに基づいてリダイレクト先を決定（Turbo対応）
        if request.referer&.include?("/tasks")
          redirect_to tasks_path, status: :see_other
        else
          redirect_to dashboard_path, status: :see_other
        end
      end
    end
  end

  def show
    respond_to do |format|
      format.html { redirect_to tasks_path, status: :see_other }
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
          redirect_to tasks_path, notice: "✅ タスク「#{@task.title}」を更新しました！", status: :see_other
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
        format.html { redirect_to tasks_path, alert: "LINE連携されていないため通知できません。", status: :see_other }
        format.json { render json: { success: false, error: "LINE連携されていないため通知できません。" }, status: :unprocessable_entity }
      end
      return
    end

    due_text = @task.due_date.present? ? @task.due_date.strftime("%m月%d日 %H:%M") : "期限なし"
    category_name = @task.category_display || "未設定"

    message = <<~TEXT.strip
      🔔 タスクが登録されました！

      【カテゴリ】 #{category_name}
      【タスク名】 #{@task.title}
      【期限】 #{due_text}

      #{@task.description.present? ? "【詳細】\n#{@task.description}" : ""}
    TEXT

    success = ::LineBotService.new.send_message(user.line_user_id, message)

    respond_to do |format|
      if success
        format.html { redirect_to tasks_path, notice: "LINEへタスク通知を送信しました。", status: :see_other }
        format.json { render json: { success: true, message: "LINEへタスク通知を送信しました。" }, status: :ok }
      else
        format.html { redirect_to tasks_path, alert: "LINE通知の送信に失敗しました。", status: :see_other }
        format.json { render json: { success: false, error: "LINE通知の送信に失敗しました。" }, status: :unprocessable_entity }
      end
    end
  rescue LoadError => e
    Rails.logger.error("[Tasks#notify_line] LoadError: #{e.class} - #{e.message}")
    respond_to do |format|
      format.html { redirect_to tasks_path, alert: "LINEライブラリの読み込みに失敗しました。", status: :see_other }
      format.json { render json: { success: false, error: "LINEライブラリの読み込みに失敗しました。", details: e.message }, status: :internal_server_error }
    end
  rescue NameError => e
    Rails.logger.error("[Tasks#notify_line] NameError: #{e.class} - #{e.message}")
    respond_to do |format|
      format.html { redirect_to tasks_path, alert: "LINE通知中に定数エラーが発生しました。", status: :see_other }
      format.json { render json: { success: false, error: "LINE通知中に定数エラーが発生しました。", details: e.message }, status: :internal_server_error }
    end
  rescue StandardError => e
    Rails.logger.error("[Tasks#notify_line] Error: #{e.class} - #{e.message}")
    respond_to do |format|
      format.html { redirect_to tasks_path, alert: "LINE通知の処理中にエラーが発生しました。", status: :see_other }
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
        render turbo_stream: [
          turbo_stream.replace("tasks-list",
            render_to_string(partial: "shared/tasks_overview", locals: { character: @character })
          ),
          turbo_stream.prepend("flash-container",
            render_to_string(partial: "shared/flash", locals: { message: "👁️ タスク「#{@task.title}」を非表示にしました", type: "success" })
          )
        ]
      end
      format.html do
        flash[:notice] = "👁️ タスク「#{@task.title}」を非表示にしました"

        # リファラーに基づいてリダイレクト先を決定（Turbo対応）
        if request.referer&.include?("/tasks")
          redirect_to tasks_path, status: :see_other
        else
          redirect_to dashboard_path, status: :see_other
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
      format.html { redirect_to dashboard_path, notice: "タスクを復元しました", status: :see_other }
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
        format.html { redirect_to tasks_path, notice: "タスク「#{@task.title}」を承認しました", status: :see_other }
        format.json { render json: { status: "approved", task_id: @task.id, message: "タスクを承認しました" } }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash-messages",
            render_to_string(partial: "shared/flash_message", locals: { message: "このタスクは承認できません", type: "error" })
          )
        end
        format.html { redirect_to tasks_path, alert: "このタスクは承認できません", status: :see_other }
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
          # タスク削除時にダッシュボードのタスク一覧全体を更新
          render turbo_stream: [
            turbo_stream.replace("tasks-list",
              render_to_string(partial: "shared/tasks_overview", locals: { character: @character })
            ),
            turbo_stream.prepend("flash-container",
              render_to_string(partial: "shared/flash", locals: { message: "「#{task_title}」を削除しました", type: "success" })
            )
          ]
        end
      end
      format.html do
        if was_draft
          redirect_to tasks_path, notice: "「#{task_title}」を却下しました", status: :see_other
        else
          redirect_to dashboard_path, notice: "タスクを完全に削除しました", status: :see_other
        end
      end
    end
  end

  private

  # HEADリクエストに対する軽量レスポンス（Turboプリフェッチ対策）
  def skip_head_requests
    Rails.logger.info "🔍 HEAD request to #{controller_name}##{action_name} - returning :ok"
    head :ok
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

  # 二重送信防止のためのヘルパーメソッド
  def generate_request_token
    # タスクのタイトル、カテゴリ、嫌い度から一意なトークンを生成
    task_data = task_params.slice(:title, :category, :dislike_level, :due_date).to_json
    Digest::SHA256.hexdigest("#{@character.id}-#{task_data}-#{Time.current.to_i / 5}")
  end

  def duplicate_request?(token)
    # セッションに同じトークンが5秒以内に記録されているかチェック
    return false unless session[:last_task_token].present?
    return false unless session[:last_task_time].present?

    session[:last_task_token] == token &&
      (Time.current - Time.at(session[:last_task_time])) < 5.seconds
  end

  def mark_request_processed(token)
    session[:last_task_token] = token
    session[:last_task_time] = Time.current.to_i
  end

  def clear_request_token(token)
    session[:last_task_token] = nil
    session[:last_task_time] = nil
  end
end
