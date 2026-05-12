# lib/tasks/line_notification.rake
namespace :line do
  desc "指定ユーザーの本日・翌日の予定をLINEへ通知する"
  task :send_daily_schedule, [ :user_id ] => :environment do |_t, args|
    user_id = args[:user_id]

    unless user_id.present?
      puts "❌ エラー: user_id を指定してください"
      puts "  使い方: bin/rails \"line:send_daily_schedule[1]\""
      exit 1
    end

    user = User.find_by(id: user_id)
    unless user
      puts "❌ ユーザーが見つかりません (id=#{user_id})"
      exit 1
    end

    if user.line_user_id.blank?
      puts "❌ user.line_user_id が未設定です (id=#{user_id})"
      exit 1
    end

    notifier = ScheduleNotifierService.new
    success = notifier.notify_user(user.id)

    if success
      puts "✅ 予定通知を送信しました (user_id=#{user.id})"
    else
      puts "❌ 予定通知の送信に失敗しました (user_id=#{user.id})"
      exit 1
    end
  end
end
