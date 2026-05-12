# app/jobs/send_line_reminder_job.rb
# 特定のイベントに対してLINEリマインドを送信するJob
class SendLineReminderJob < ApplicationJob
  queue_as :default

  # @param event_id [Integer] リマインド対象のEvent ID
  def perform(event_id)
    event = Event.includes(character: :user).find_by(id: event_id)
    unless event
      Rails.logger.warn("[LINE Reminder] Event #{event_id} not found, skipping.")
      return
    end

    line_user_id = event.character&.user&.line_user_id
    unless line_user_id.present?
      Rails.logger.info("[LINE Reminder] User for Event #{event_id} has no line_user_id, skipping.")
      return
    end

    service = LineBotService.new
    success = service.send_event_reminder(line_user_id, event)

    if success
      Rails.logger.info("[LINE Reminder] Sent reminder for Event #{event_id} to #{line_user_id}")
    else
      Rails.logger.error("[LINE Reminder] Failed to send reminder for Event #{event_id}")
    end
  end
end
