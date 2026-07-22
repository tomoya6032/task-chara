# 特定タスクに対して72時間前のLINE通知を送信するJob
class SendTaskDueReminderJob < ApplicationJob
  queue_as :default

  # リトライ設定: 最大3回、指数バックオフ
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # @param task_id [Integer] 通知対象のTask ID
  def perform(task_id)
    task = Task.includes(character: :user).find_by(id: task_id)
    unless task
      Rails.logger.warn("[SendTaskDueReminderJob] ⚠️ Task #{task_id} が見つかりません。スキップ。")
      return
    end

    line_user_id = task.character&.user&.line_user_id
    unless line_user_id.present?
      Rails.logger.info("[SendTaskDueReminderJob] ⚠️ Task #{task_id} のユーザーにline_user_idがありません。スキップ。")
      return
    end

    # 既に完了済みの場合はスキップ
    if task.completed?
      Rails.logger.info("[SendTaskDueReminderJob] ℹ️ Task #{task_id} は既に完了済み。スキップ。")
      return
    end

    begin
      Rails.logger.info("[SendTaskDueReminderJob] 📤 送信開始: Task #{task_id} (#{task.title}) → #{line_user_id}")

      service = LineBotService.new
      success = service.send_task_due_reminder(line_user_id, task)

      if success
        Rails.logger.info("[SendTaskDueReminderJob] ✅ 送信成功: Task #{task_id} → #{line_user_id}")
      else
        # 送信失敗時はフラグをリセットして再試行可能にする
        task.update_columns(line_due_72h_notified_at: nil)
        Rails.logger.error("[SendTaskDueReminderJob] ❌ 送信失敗: Task #{task_id} - LINE API がfalseを返しました")
        # 失敗時は例外を発生させてリトライ
        raise "LINE API returned false for task #{task_id}"
      end

    rescue => e
      # エラー時もフラグをリセット
      task.update_columns(line_due_72h_notified_at: nil) rescue nil
      Rails.logger.error("[SendTaskDueReminderJob] ❌ 送信エラー: Task #{task_id} - #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(3).join("\n"))
      raise # リトライを発動
    end
  end
end
