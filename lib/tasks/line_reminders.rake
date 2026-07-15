# lib/tasks/line_reminders.rake
# LINEリマインド自動送信タスク
#
# 使い方:
#   bin/rails reminders:send_event_reminders      # イベントのリマインド送信
#   bin/rails reminders:send_task_reminders       # タスクの72時間前リマインド送信
#   bin/rails reminders:send_all                  # 両方実行
#
# Heroku Schedulerでの設定:
#   bin/rails reminders:send_all を10分ごとに実行

namespace :reminders do
  desc "カレンダーイベントのLINEリマインドを送信"
  task send_event_reminders: :environment do
    puts "=" * 80
    puts "[#{Time.current}] イベントリマインド送信タスク開始"
    puts "=" * 80

    # LINE認証情報が設定されているか確認
    unless LineBotService.credentials_configured?
      puts "⚠️ LINE認証情報が設定されていません。処理をスキップします。"
      next
    end

    # リマインド対象のイベントを抽出
    # 条件:
    #   1. reminder_minutes が設定されている（nilではない）
    #   2. line_reminded_at が nil（まだ送信していない）
    #   3. リマインド時刻が現在時刻を過ぎている
    #   4. イベント開始時刻がまだ到来していない
    #   5. キャンセルされていない
    now = Time.current

    events = Event
      .joins(character: :user)
      .where.not(reminder_minutes: nil)
      .where(line_reminded_at: nil)
      .where("start_time > ?", now)
      .where.not(status: :cancelled)
      .where.not(users: { line_user_id: nil })

    puts "📊 リマインド設定されているイベント数: #{events.count}"

    sent_count = 0
    error_count = 0
    skipped_count = 0

    events.find_each do |event|
      begin
        # リマインド時刻を計算（イベント開始時刻 - reminder_minutes）
        reminder_time = event.start_time - event.reminder_minutes.minutes

        # リマインド時刻が過ぎているか確認
        if now >= reminder_time
          user = event.character.user

          if user.line_user_id.blank?
            puts "⏭️ スキップ: イベント「#{event.title}」- LINE未連携"
            skipped_count += 1
            next
          end

          # LINEリマインドを送信
          service = LineBotService.new
          success = service.send_event_reminder(user.line_user_id, event)

          if success
            # 送信成功したら line_reminded_at を更新
            event.update_column(:line_reminded_at, now)
            puts "✅ 送信成功: イベント「#{event.title}」(ID: #{event.id}) → #{user.line_user_id}"
            sent_count += 1
          else
            puts "❌ 送信失敗: イベント「#{event.title}」(ID: #{event.id})"
            error_count += 1
          end
        else
          # まだリマインド時刻に達していない
          time_until_reminder = ((reminder_time - now) / 60).round
          puts "⏰ 待機中: イベント「#{event.title}」- あと#{time_until_reminder}分後に送信予定"
          skipped_count += 1
        end
      rescue StandardError => e
        puts "❌ エラー: イベント「#{event.title}」(ID: #{event.id}) - #{e.class}: #{e.message}"
        Rails.logger.error("[reminders:send_event_reminders] Error: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
        error_count += 1
      end
    end

    puts ""
    puts "=" * 80
    puts "📊 実行結果サマリー"
    puts "=" * 80
    puts "✅ 送信成功: #{sent_count}件"
    puts "❌ 送信失敗: #{error_count}件"
    puts "⏭️ スキップ: #{skipped_count}件"
    puts "🏁 タスク完了: #{Time.current}"
    puts "=" * 80
  end

  desc "タスクの72時間前LINEリマインドを送信"
  task send_task_reminders: :environment do
    puts "=" * 80
    puts "[#{Time.current}] タスクリマインド送信タスク開始"
    puts "=" * 80

    # LINE認証情報が設定されているか確認
    unless LineBotService.credentials_configured?
      puts "⚠️ LINE認証情報が設定されていません。処理をスキップします。"
      next
    end

    # リマインド対象のタスクを抽出
    # 条件:
    #   1. due_date が設定されている（nilではない）
    #   2. line_due_72h_notified_at が nil（まだ送信していない）
    #   3. due_date が現在時刻から72時間以内
    #   4. 完了していない（completed_at が nil）
    #   5. 非表示ではない
    now = Time.current
    reminder_window_start = now
    reminder_window_end = now + 72.hours

    tasks = Task
      .joins(character: :user)
      .where.not(due_date: nil)
      .where(line_due_72h_notified_at: nil)
      .where(completed_at: nil)
      .where("hidden IS NULL OR hidden = ?", false)
      .where("due_date BETWEEN ? AND ?", reminder_window_start, reminder_window_end)
      .where.not(users: { line_user_id: nil })

    puts "📊 リマインド対象のタスク数: #{tasks.count}"

    sent_count = 0
    error_count = 0
    skipped_count = 0

    tasks.find_each do |task|
      begin
        user = task.character.user

        if user.line_user_id.blank?
          puts "⏭️ スキップ: タスク「#{task.title}」- LINE未連携"
          skipped_count += 1
          next
        end

        # 期限までの残り時間を計算
        hours_until_due = ((task.due_date - now) / 3600).round(1)

        # LINEリマインドを送信
        service = LineBotService.new
        success = service.send_task_due_reminder(user.line_user_id, task)

        if success
          # 送信成功したら line_due_72h_notified_at を更新
          task.update_column(:line_due_72h_notified_at, now)
          puts "✅ 送信成功: タスク「#{task.title}」(ID: #{task.id}) - 期限まで#{hours_until_due}時間 → #{user.line_user_id}"
          sent_count += 1
        else
          puts "❌ 送信失敗: タスク「#{task.title}」(ID: #{task.id})"
          error_count += 1
        end
      rescue StandardError => e
        puts "❌ エラー: タスク「#{task.title}」(ID: #{task.id}) - #{e.class}: #{e.message}"
        Rails.logger.error("[reminders:send_task_reminders] Error: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}")
        error_count += 1
      end
    end

    puts ""
    puts "=" * 80
    puts "📊 実行結果サマリー"
    puts "=" * 80
    puts "✅ 送信成功: #{sent_count}件"
    puts "❌ 送信失敗: #{error_count}件"
    puts "⏭️ スキップ: #{skipped_count}件"
    puts "🏁 タスク完了: #{Time.current}"
    puts "=" * 80
  end

  desc "すべてのLINEリマインドを送信（イベント + タスク）"
  task send_all: :environment do
    puts ""
    puts "🚀 すべてのリマインド送信タスクを開始します"
    puts ""

    Rake::Task["reminders:send_event_reminders"].invoke
    puts ""
    Rake::Task["reminders:send_task_reminders"].invoke

    puts ""
    puts "🎉 すべてのリマインド送信タスクが完了しました"
    puts ""
  end
end
