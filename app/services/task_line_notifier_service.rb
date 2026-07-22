# app/services/task_line_notifier_service.rb
# AIエージェントからの指示に基づいてタスクをLINEに送信するサービス

class TaskLineNotifierService
  attr_reader :character, :user, :filters

  # @param character [Character] タスクを取得するキャラクター
  # @param filters [Hash] タスク抽出条件
  #   - time_frame: "today", "tomorrow", "this_week", "next_week", "overdue"
  #   - limit: 取得件数（デフォルト: 10）
  #   - filter_type: "nearing_deadline", "uncompleted", "all"
  def initialize(character:, filters: {})
    @character = character
    @user = character&.user
    @filters = filters.with_indifferent_access
  end

  # タスクを抽出してLINEに送信
  # @return [Hash] { success: Boolean, message: String, tasks_count: Integer }
  def send_tasks_to_line
    # LINE連携チェック
    unless user&.line_user_id.present?
      return {
        success: false,
        message: "LINE連携が完了していません。設定画面からLINE連携を行ってください。",
        tasks_count: 0
      }
    end

    # タスクを抽出
    tasks = extract_tasks

    if tasks.empty?
      return {
        success: false,
        message: "指定された条件に一致するタスクが見つかりませんでした。",
        tasks_count: 0
      }
    end

    # LINEメッセージを構築
    message = build_line_message(tasks)

    # LINE送信
    service = LineBotService.new
    success = service.send_message(user.line_user_id, message)

    if success
      {
        success: true,
        message: "#{tasks.count}件のタスクをLINEに送信しました！",
        tasks_count: tasks.count
      }
    else
      {
        success: false,
        message: "LINEへの送信に失敗しました。しばらく経ってから再度お試しください。",
        tasks_count: 0
      }
    end
  rescue => e
    Rails.logger.error("[TaskLineNotifierService] Error: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    {
      success: false,
      message: "エラーが発生しました: #{e.message}",
      tasks_count: 0
    }
  end

  private

  # タスクを抽出
  def extract_tasks
    scope = character.tasks.pending.visible.published

    # 時間枠フィルタ
    scope = apply_time_frame_filter(scope)

    # フィルタータイプ
    scope = apply_filter_type(scope)

    # 並び順
    scope = scope.ordered_by_due_date

    # 件数制限
    limit = filters[:limit].to_i
    limit = 10 if limit <= 0 || limit > 50
    scope = scope.limit(limit)

    scope.to_a
  end

  # 時間枠フィルタを適用
  def apply_time_frame_filter(scope)
    case filters[:time_frame]
    when "today"
      today_start = Time.current.beginning_of_day
      today_end = Time.current.end_of_day
      scope.where(due_date: today_start..today_end)
    when "tomorrow"
      tomorrow_start = 1.day.from_now.beginning_of_day
      tomorrow_end = 1.day.from_now.end_of_day
      scope.where(due_date: tomorrow_start..tomorrow_end)
    when "this_week"
      week_start = Time.current.beginning_of_week
      week_end = Time.current.end_of_week
      scope.where(due_date: week_start..week_end)
    when "next_week"
      next_week_start = 1.week.from_now.beginning_of_week
      next_week_end = 1.week.from_now.end_of_week
      scope.where(due_date: next_week_start..next_week_end)
    when "overdue"
      scope.where("due_date < ?", Time.current)
    else
      scope
    end
  end

  # フィルタータイプを適用
  def apply_filter_type(scope)
    case filters[:filter_type]
    when "nearing_deadline"
      # 期限が近い順（48時間以内）
      scope.where(due_date: Time.current..(48.hours.from_now))
    when "uncompleted"
      # すでにpendingスコープがかかっているのでそのまま
      scope
    when "all"
      scope
    else
      scope
    end
  end

  # LINEメッセージを構築
  def build_line_message(tasks)
    header = build_message_header(tasks.count)
    task_list = build_task_list(tasks)

    <<~MESSAGE.strip
      #{header}
      --------------------
      #{task_list}
      --------------------
      タスク管理アプリで詳細を確認できます 📱
    MESSAGE
  end

  # メッセージヘッダーを構築
  def build_message_header(count)
    case filters[:time_frame]
    when "today"
      "📅 今日のタスク（#{count}件）"
    when "tomorrow"
      "📅 明日のタスク（#{count}件）"
    when "this_week"
      "📅 今週のタスク（#{count}件）"
    when "next_week"
      "📅 来週のタスク（#{count}件）"
    when "overdue"
      "⚠️ 期限切れタスク（#{count}件）"
    else
      case filters[:filter_type]
      when "nearing_deadline"
        "⏰ 期限が近いタスク（#{count}件）"
      else
        "📋 未完了タスク（#{count}件）"
      end
    end
  end

  # タスクリストを構築
  def build_task_list(tasks)
    tasks.map.with_index(1) do |task, index|
      category_name = task.category_display || "未設定"
      due_text = format_due_date(task.due_date)

      "#{index}. [#{category_name}] #{task.title}#{due_text}"
    end.join("\n")
  end

  # 期限日時をフォーマット
  def format_due_date(due_date)
    return "" unless due_date.present?

    now = Time.current
    diff_hours = ((due_date - now) / 3600).round

    if diff_hours < 0
      " ⚠️ 期限切れ"
    elsif diff_hours < 3
      " ⏰ #{diff_hours}時間以内"
    elsif due_date.to_date == now.to_date
      " (今日 #{due_date.strftime('%H:%M')})"
    elsif due_date.to_date == now.tomorrow.to_date
      " (明日 #{due_date.strftime('%H:%M')})"
    else
      " (#{due_date.strftime('%m/%d %H:%M')})"
    end
  end
end
