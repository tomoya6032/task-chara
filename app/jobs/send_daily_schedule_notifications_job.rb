# 毎日7時に、LINE連携済みユーザーへ本日・翌日の予定を通知するJob
class SendDailyScheduleNotificationsJob < ApplicationJob
  queue_as :default

  def perform
    notifier = ScheduleNotifierService.new
    success_count = 0
    failed_count = 0

    User.where.not(line_user_id: [ nil, "" ]).find_each do |user|
      if notifier.notify_user(user.id)
        success_count += 1
      else
        failed_count += 1
      end
    rescue => e
      failed_count += 1
      Rails.logger.error("[LINE DailySchedule] user_id=#{user.id} failed: #{e.class} - #{e.message}")
    end

    Rails.logger.info("[LINE DailySchedule] completed: success=#{success_count}, failed=#{failed_count}")
  end
end
