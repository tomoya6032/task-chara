# lib/tasks/reminder_test.rake
# LINEリマインド機能の手動テスト・デバッグ用タスク

namespace :reminders do
  namespace :test do
    desc "【テスト】指定したEvent IDに対してリマインドを即座に送信"
    task :send_event, [ :event_id ] => :environment do |t, args|
      unless args[:event_id].present?
        puts "❌ エラー: Event IDを指定してください"
        puts "使用例: bin/rails 'reminders:test:send_event[123]'"
        next
      end

      event_id = args[:event_id].to_i
      event = Event.find_by(id: event_id)

      unless event
        puts "❌ エラー: Event ID #{event_id} が見つかりません"
        next
      end

      puts "=" * 80
      puts "【テスト送信】Event ID: #{event_id}"
      puts "=" * 80
      puts "タイトル: #{event.title}"
      puts "開始時刻: #{event.start_time.strftime('%Y-%m-%d %H:%M:%S %Z')}"
      puts "リマインド設定: #{event.reminder_minutes}分前"
      puts "ユーザーLINE ID: #{event.character&.user&.line_user_id || 'なし'}"
      puts "送信済みフラグ: #{event.line_reminded_at || 'なし'}"
      puts ""

      unless event.character&.user&.line_user_id.present?
        puts "❌ エラー: このイベントのユーザーはLINE連携していません"
        next
      end

      unless LineBotService.credentials_configured?
        puts "❌ エラー: LINE認証情報が設定されていません"
        next
      end

      print "送信中..."
      service = LineBotService.new
      success = service.send_event_reminder(event.character.user.line_user_id, event)

      if success
        event.update_column(:line_reminded_at, Time.current)
        puts " ✅ 送信成功！"
        puts "line_reminded_at を更新しました: #{event.reload.line_reminded_at}"
      else
        puts " ❌ 送信失敗"
      end
      puts "=" * 80
    end

    desc "【テスト】指定したTask IDに対してリマインドを即座に送信"
    task :send_task, [ :task_id ] => :environment do |t, args|
      unless args[:task_id].present?
        puts "❌ エラー: Task IDを指定してください"
        puts "使用例: bin/rails 'reminders:test:send_task[456]'"
        next
      end

      task_id = args[:task_id].to_i
      task = Task.find_by(id: task_id)

      unless task
        puts "❌ エラー: Task ID #{task_id} が見つかりません"
        next
      end

      puts "=" * 80
      puts "【テスト送信】Task ID: #{task_id}"
      puts "=" * 80
      puts "タイトル: #{task.title}"
      puts "期限: #{task.due_date&.strftime('%Y-%m-%d %H:%M:%S %Z') || '期限なし'}"
      puts "ユーザーLINE ID: #{task.character&.user&.line_user_id || 'なし'}"
      puts "送信済みフラグ: #{task.line_due_72h_notified_at || 'なし'}"
      puts ""

      unless task.character&.user&.line_user_id.present?
        puts "❌ エラー: このタスクのユーザーはLINE連携していません"
        next
      end

      unless LineBotService.credentials_configured?
        puts "❌ エラー: LINE認証情報が設定されていません"
        next
      end

      print "送信中..."
      service = LineBotService.new
      success = service.send_task_due_reminder(task.character.user.line_user_id, task)

      if success
        task.update_column(:line_due_72h_notified_at, Time.current)
        puts " ✅ 送信成功！"
        puts "line_due_72h_notified_at を更新しました: #{task.reload.line_due_72h_notified_at}"
      else
        puts " ❌ 送信失敗"
      end
      puts "=" * 80
    end

    desc "【テスト】CheckEventRemindersJobを手動実行"
    task run_event_job: :environment do
      puts "=" * 80
      puts "【手動実行】CheckEventRemindersJob"
      puts "=" * 80
      puts "現在時刻: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}"
      puts ""

      CheckEventRemindersJob.new.perform

      puts ""
      puts "✅ ジョブ実行完了"
      puts "=" * 80
    end

    desc "【テスト】CheckTaskDueRemindersJobを手動実行"
    task run_task_job: :environment do
      puts "=" * 80
      puts "【手動実行】CheckTaskDueRemindersJob"
      puts "=" * 80
      puts "現在時刻: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}"
      puts ""

      CheckTaskDueRemindersJob.new.perform

      puts ""
      puts "✅ ジョブ実行完了"
      puts "=" * 80
    end

    desc "【テスト】リマインド対象イベントを一覧表示（送信なし）"
    task list_events: :environment do
      now = Time.current
      puts "=" * 80
      puts "【リマインド対象イベント一覧】"
      puts "=" * 80
      puts "現在時刻: #{now.strftime('%Y-%m-%d %H:%M:%S %Z')}"
      puts ""

      [ 30, 60, 180, 1440, 4320 ].each do |minutes|
        target_time = now + minutes.minutes

        events = Event
          .joins(character: :user)
          .where(reminder_minutes: minutes)
          .where(line_reminded_at: nil)
          .where("events.start_time > ?", now)
          .where(cancelled_at: nil)
          .where.not(users: { line_user_id: nil })
          .order(:start_time)

        puts "━━━ #{minutes}分前リマインド（対象: #{target_time.strftime('%Y-%m-%d %H:%M')} 頃開始）━━━"

        if events.count == 0
          puts "  対象なし"
        else
          events.each do |event|
            reminder_time = event.start_time - event.reminder_minutes.minutes
            time_until = ((reminder_time - now) / 60).round
            puts "  • ID:#{event.id} 「#{event.title}」"
            puts "    開始: #{event.start_time.strftime('%Y-%m-%d %H:%M')}"
            puts "    送信予定: #{reminder_time.strftime('%Y-%m-%d %H:%M')} (あと#{time_until}分)"
          end
        end
        puts ""
      end
      puts "=" * 80
    end

    desc "【テスト】リマインド対象タスクを一覧表示（送信なし）"
    task list_tasks: :environment do
      now = Time.current
      remind_start = now + 71.5.hours
      remind_end = now + 72.5.hours

      puts "=" * 80
      puts "【72時間前リマインド対象タスク一覧】"
      puts "=" * 80
      puts "現在時刻: #{now.strftime('%Y-%m-%d %H:%M:%S %Z')}"
      puts "対象期限: #{remind_start.strftime('%Y-%m-%d %H:%M')} ～ #{remind_end.strftime('%Y-%m-%d %H:%M')}"
      puts ""

      tasks = Task
        .pending
        .published
        .joins(character: :user)
        .where(line_due_72h_notified_at: nil)
        .where(due_date: remind_start..remind_end)
        .where.not(users: { line_user_id: nil })
        .order(:due_date)

      if tasks.count == 0
        puts "対象なし"
      else
        puts "対象: #{tasks.count}件"
        puts ""
        tasks.each do |task|
          time_until = ((task.due_date - now) / 3600).round(1)
          puts "  • ID:#{task.id} 「#{task.title}」"
          puts "    期限: #{task.due_date.strftime('%Y-%m-%d %H:%M')} (あと#{time_until}時間)"
          puts "    送信済み: #{task.line_due_72h_notified_at || 'なし'}"
        end
      end
      puts ""
      puts "=" * 80
    end

    desc "【テスト】送信フラグをリセット（Event ID指定）"
    task :reset_event, [ :event_id ] => :environment do |t, args|
      unless args[:event_id].present?
        puts "❌ エラー: Event IDを指定してください"
        puts "使用例: bin/rails 'reminders:test:reset_event[123]'"
        next
      end

      event_id = args[:event_id].to_i
      event = Event.find_by(id: event_id)

      unless event
        puts "❌ エラー: Event ID #{event_id} が見つかりません"
        next
      end

      old_value = event.line_reminded_at
      event.update_column(:line_reminded_at, nil)

      puts "✅ Event ID #{event_id} の送信フラグをリセットしました"
      puts "  旧: #{old_value}"
      puts "  新: #{event.reload.line_reminded_at || 'nil'}"
    end

    desc "【テスト】送信フラグをリセット（Task ID指定）"
    task :reset_task, [ :task_id ] => :environment do |t, args|
      unless args[:task_id].present?
        puts "❌ エラー: Task IDを指定してください"
        puts "使用例: bin/rails 'reminders:test:reset_task[456]'"
        next
      end

      task_id = args[:task_id].to_i
      task = Task.find_by(id: task_id)

      unless task
        puts "❌ エラー: Task ID #{task_id} が見つかりません"
        next
      end

      old_value = task.line_due_72h_notified_at
      task.update_column(:line_due_72h_notified_at, nil)

      puts "✅ Task ID #{task_id} の送信フラグをリセットしました"
      puts "  旧: #{old_value}"
      puts "  新: #{task.reload.line_due_72h_notified_at || 'nil'}"
    end
  end
end
