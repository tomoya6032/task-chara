# app/jobs/check_event_reminders_job.rb
# 毎分実行し、各イベントの reminder_minutes に応じたタイミングでLINEリマインドを送信するJob
class CheckEventRemindersJob < ApplicationJob
  queue_as :default

  # チェックウィンドウ（Jobが1分ごとに実行される想定でズレを吸収）
  WINDOW_SECONDS = 90

  def perform
    now = Time.current

    # reminder_minutes が設定されているイベントを対象に検索
    # reminder_minutes 分後が now の前後 WINDOW_SECONDS 秒以内のものを抽出
    Event.includes(character: :user)
         .where.not(reminder_minutes: nil)
         .find_each do |event|
      remind_at = event.start_time - event.reminder_minutes.minutes
      next unless remind_at.between?(now - WINDOW_SECONDS.seconds, now + WINDOW_SECONDS.seconds)
      next unless event.character&.user&.line_user_id.present?
      next if already_reminded?(event)

      mark_as_reminded!(event)
      SendLineReminderJob.perform_later(event.id)
      Rails.logger.info("[CheckReminders] Queued reminder for Event #{event.id} (#{event.title}) - #{event.reminder_minutes}分前")
    end
  end

  private

  def already_reminded?(event)
    event.metadata.is_a?(Hash) && event.metadata["line_reminder_sent_at"].present?
  end

  def mark_as_reminded!(event)
    meta = event.metadata.is_a?(Hash) ? event.metadata.dup : {}
    meta["line_reminder_sent_at"] = Time.current.iso8601
    event.update_columns(metadata: meta)
  end
end
