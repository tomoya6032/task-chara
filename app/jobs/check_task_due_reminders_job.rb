# 毎分実行し、72時間後に期限を迎えるタスクがあればLINEリマインドを送信するJob
class CheckTaskDueRemindersJob < ApplicationJob
  queue_as :default

  REMIND_BEFORE_HOURS = 72
  WINDOW_SECONDS = 90

  def perform
    remind_at_start = Time.current + (REMIND_BEFORE_HOURS.hours - WINDOW_SECONDS.seconds)
    remind_at_end   = Time.current + (REMIND_BEFORE_HOURS.hours + WINDOW_SECONDS.seconds)

    tasks = Task
      .pending
      .published
      .includes(character: :user)
      .where(due_date: remind_at_start..remind_at_end, line_due_72h_notified_at: nil)

    tasks.find_each do |task|
      next unless task.character&.user&.line_user_id.present?

      mark_as_queued!(task)
      SendTaskDueReminderJob.perform_later(task.id)
      Rails.logger.info("[CheckTaskDueReminders] Queued reminder for Task #{task.id} (#{task.title})")
    end
  end

  private

  def mark_as_queued!(task)
    task.update_columns(line_due_72h_notified_at: Time.current)
  end
end
