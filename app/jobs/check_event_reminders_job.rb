# app/jobs/check_event_reminders_job.rb
# 毎分実行し、15分後に開始するイベントがあればLINEリマインドを送信するJob
# recurring.yml で "every minute" に設定して使用する
class CheckEventRemindersJob < ApplicationJob
  queue_as :default

  # リマインドを送る「開始何分前」
  REMIND_BEFORE_MINUTES = 15
  # チェックウィンドウ（このJobが1分ごとに実行される想定でズレを吸収）
  WINDOW_SECONDS = 90

  def perform
    remind_at_start = Time.current + (REMIND_BEFORE_MINUTES.minutes - WINDOW_SECONDS.seconds)
    remind_at_end   = Time.current + (REMIND_BEFORE_MINUTES.minutes + WINDOW_SECONDS.seconds)

    events = Event
      .includes(character: :user)
      .where(start_time: remind_at_start..remind_at_end)

    events.each do |event|
      next unless event.character&.user&.line_user_id.present?
      next if already_reminded?(event)

      mark_as_reminded!(event)
      SendLineReminderJob.perform_later(event.id)
      Rails.logger.info("[CheckReminders] Queued reminder for Event #{event.id} (#{event.title})")
    end
  end

  private

  # metadata に line_reminder_sent_at が保存されていれば送信済みとみなす
  def already_reminded?(event)
    event.metadata.is_a?(Hash) && event.metadata["line_reminder_sent_at"].present?
  end

  # event.metadata に送信済みフラグを書き込む
  def mark_as_reminded!(event)
    meta = event.metadata.is_a?(Hash) ? event.metadata.dup : {}
    meta["line_reminder_sent_at"] = Time.current.iso8601
    event.update_columns(metadata: meta)
  end
end
