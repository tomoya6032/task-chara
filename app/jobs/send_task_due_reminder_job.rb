# 特定タスクに対して72時間前のLINE通知を送信するJob
class SendTaskDueReminderJob < ApplicationJob
  queue_as :default

  # @param task_id [Integer] 通知対象のTask ID
  def perform(task_id)
    task = Task.includes(character: :user).find_by(id: task_id)
    unless task
      Rails.logger.warn("[TaskDueReminder] Task #{task_id} not found, skipping.")
      return
    end

    line_user_id = task.character&.user&.line_user_id
    unless line_user_id.present?
      Rails.logger.info("[TaskDueReminder] Task #{task_id} has no line_user_id, skipping.")
      return
    end

    success = LineBotService.new.send_task_due_reminder(line_user_id, task)

    if success
      Rails.logger.info("[TaskDueReminder] Sent 72h reminder for Task #{task.id} to #{line_user_id}")
    else
      task.update_columns(line_due_72h_notified_at: nil)
      Rails.logger.error("[TaskDueReminder] Failed to send reminder for Task #{task.id}")
    end
  end
end
