# 毎分実行し、72時間後に期限を迎えるタスクがあればLINEリマインドを送信するJob
class CheckTaskDueRemindersJob < ApplicationJob
  queue_as :default

  REMIND_BEFORE_HOURS = 72
  WINDOW_SECONDS = 90

  def perform
    now = Time.current

    Rails.logger.info("[CheckTaskDueRemindersJob] 実行開始 - 現在時刻: #{now.strftime('%Y-%m-%d %H:%M:%S %Z')}")

    # LINE認証情報が設定されているか確認
    unless LineBotService.credentials_configured?
      Rails.logger.warn("[CheckTaskDueRemindersJob] LINE認証情報が未設定のため処理をスキップ")
      return
    end

    begin
      remind_at_start = now + (REMIND_BEFORE_HOURS.hours - WINDOW_SECONDS.seconds)
      remind_at_end   = now + (REMIND_BEFORE_HOURS.hours + WINDOW_SECONDS.seconds)

      tasks = Task
        .pending
        .published
        .includes(character: :user)
        .where(due_date: remind_at_start..remind_at_end, line_due_72h_notified_at: nil)
        .where.not(users: { line_user_id: nil })

      Rails.logger.info("[CheckTaskDueRemindersJob] 対象タスク数: #{tasks.count}件")

      tasks.find_each do |task|
        begin
          next unless task.character&.user&.line_user_id.present?

          # フラグを即座に更新して重複送信を防止
          mark_as_queued!(task)

          SendTaskDueReminderJob.perform_later(task.id)
          Rails.logger.info("[CheckTaskDueRemindersJob] ✅ キュー登録: Task #{task.id} (#{task.title})")

        rescue => e
          Rails.logger.error("[CheckTaskDueRemindersJob] ❌ Task #{task.id} のキュー登録エラー: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace.first(3).join("\n"))
        end
      end

      Rails.logger.info("[CheckTaskDueRemindersJob] 実行完了")

    rescue => e
      Rails.logger.error("[CheckTaskDueRemindersJob] ❌ 予期しないエラー: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      raise # ジョブをリトライさせる
    end
  end

  private

  def mark_as_queued!(task)
    task.update_columns(line_due_72h_notified_at: Time.current)
  end
end
