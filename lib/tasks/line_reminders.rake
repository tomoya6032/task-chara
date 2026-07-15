# lib/tasks/line_reminders.rake
# LINEリマインド自動送信タスク
#
# 使い方:
#   bin/rails reminders:send_event_reminders      # イベントのリマインド送信
#   bin/rails reminders:send_task_reminders       # タスクの72時間前リマインド送信
#   bin/rails reminders:send_all                  # 両方実行
#   bin/rails reminders:send_line                 # エイリアス（send_allと同じ）
#
# Heroku Schedulerでの設定:
#   bin/rails reminders:send_all を10分ごとに実行

namespace :reminders do
  desc "カレンダーイベントのLINEリマインドを送信"
  task send_event_reminders: :environment do
    puts ""
    puts "=" * 80
    puts "--- LINEリマインド判定開始（イベント） ---"
    puts "=" * 80

    # タイムゾーン情報を出力
    now = Time.zone.now
    puts "🕐 現在時刻（JST）: #{now.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    puts "🕐 現在時刻（UTC）: #{now.utc.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    puts "🌏 アプリケーションタイムゾーン: #{Time.zone.name}"
    puts "🌏 サーバータイムゾーン: #{ENV['TZ'] || 'デフォルト（UTC）'}"
    puts ""

    # LINE認証情報が設定されているか確認
    unless LineBotService.credentials_configured?
      puts "⚠️ LINE認証情報が設定されていません。処理をスキップします。"
      Rails.logger.warn("[reminders:send_event_reminders] LINE認証情報が未設定")
      next
    end
    puts "✅ LINE認証情報: 設定済み"
    puts ""

    # まずデータベースの全イベント数を確認
    total_events = Event.count
    puts "📊 データベース内の全イベント数: #{total_events}件"

    # reminder_minutes が設定されているイベント数
    events_with_reminder = Event.where.not(reminder_minutes: nil).count
    puts "📊 リマインド設定されている全イベント数: #{events_with_reminder}件"

    # 未送信のイベント数
    events_not_sent = Event.where.not(reminder_minutes: nil).where(line_reminded_at: nil).count
    puts "📊 まだリマインド未送信のイベント数: #{events_not_sent}件"
    puts ""

    # リマインド対象のイベントを抽出
    # 条件:
    #   1. reminder_minutes が設定されている（nilではない）
    #   2. line_reminded_at が nil（まだ送信していない）
    #   3. イベント開始時刻が過去24時間以内または未来（リマインドの意味がある範囲）
    #   4. キャンセルされていない
    #   5. LINE連携済みユーザー
    puts "🔍 検索条件:"
    puts "  1. reminder_minutes が nil でない"
    puts "  2. line_reminded_at が nil（未送信）"
    puts "  3. start_time >= #{(now - 24.hours).strftime('%Y-%m-%d %H:%M:%S')}（過去24時間以内または未来）"
    puts "  4. status が cancelled でない"
    puts "  5. users.line_user_id が nil でない"
    puts ""

    events = Event
      .joins(character: :user)
      .where.not(reminder_minutes: nil)
      .where(line_reminded_at: nil)
      .where("events.start_time >= ?", now - 24.hours)  # 過去24時間以内または未来
      .where.not(status: :cancelled)
      .where.not(users: { line_user_id: nil })

    puts "📊 リマインド対象候補数: #{events.count}件"
    puts ""

    if events.count > 0
      puts "📋 対象イベント一覧:"
      events.each do |event|
        reminder_time = event.start_time - event.reminder_minutes.minutes
        time_diff = ((reminder_time - now) / 60).round
        puts "  - ID:#{event.id} 「#{event.title}」"
        puts "    開始: #{event.start_time.strftime('%Y-%m-%d %H:%M:%S %Z')}"
        puts "    リマインド設定: #{event.reminder_minutes}分前"
        puts "    リマインド送信時刻: #{reminder_time.strftime('%Y-%m-%d %H:%M:%S %Z')}"
        puts "    現在からの差: #{time_diff}分#{time_diff > 0 ? '後' : '前'}"
        puts "    送信済みフラグ: #{event.line_reminded_at.present? ? event.line_reminded_at : 'nil（未送信）'}"
        puts "    ユーザーLINE ID: #{event.character&.user&.line_user_id || 'なし'}"
        puts ""
      end
    end

    Rails.logger.info("[reminders:send_event_reminders] 現在時刻: #{now}, 対象候補: #{events.count}件")

    sent_count = 0
    error_count = 0
    skipped_count = 0

    events.find_each do |event|
      begin
        # リマインド時刻を計算（イベント開始時刻 - reminder_minutes）
        reminder_time = event.start_time - event.reminder_minutes.minutes

        puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        puts "🔔 処理中: イベント「#{event.title}」(ID: #{event.id})"
        puts "  開始時刻: #{event.start_time.strftime('%Y-%m-%d %H:%M:%S %Z')}"
        puts "  リマインド時刻: #{reminder_time.strftime('%Y-%m-%d %H:%M:%S %Z')}"
        puts "  現在時刻: #{now.strftime('%Y-%m-%d %H:%M:%S %Z')}"

        # イベントが既に開始している場合はスキップ
        if now > event.start_time
          puts "  判定: ⏭️ イベントは既に開始済み → スキップ"
          Rails.logger.info("[reminders:send_event_reminders] スキップ: イベントID #{event.id} - 既に開始済み")
          skipped_count += 1
          next
        end

        # リマインド時刻が過ぎているか確認
        if now >= reminder_time
          puts "  判定: ✅ リマインド時刻を過ぎています → 送信対象"

          user = event.character.user

          if user.line_user_id.blank?
            puts "  結果: ⏭️ スキップ（LINE未連携）"
            Rails.logger.warn("[reminders:send_event_reminders] スキップ: イベントID #{event.id} - LINE未連携")
            skipped_count += 1
            next
          end

          puts "  LINE送信先: #{user.line_user_id}"
          puts "  送信開始..."

          # LINEリマインドを送信
          service = LineBotService.new
          success = service.send_event_reminder(user.line_user_id, event)

          if success
            # 送信成功したら line_reminded_at を更新
            event.update_column(:line_reminded_at, now)
            puts "  結果: ✅ 送信成功！"
            Rails.logger.info("[reminders:send_event_reminders] 送信成功: イベントID #{event.id} → #{user.line_user_id}")
            sent_count += 1
          else
            puts "  結果: ❌ 送信失敗"
            Rails.logger.error("[reminders:send_event_reminders] 送信失敗: イベントID #{event.id}")
            error_count += 1
          end
        else
          # まだリマインド時刻に達していない
          time_until_reminder = ((reminder_time - now) / 60).round
          puts "  判定: ⏰ まだリマインド時刻に達していません"
          puts "  結果: ⏭️ スキップ（あと#{time_until_reminder}分後に送信予定）"
          Rails.logger.info("[reminders:send_event_reminders] 待機中: イベントID #{event.id} - あと#{time_until_reminder}分")
          skipped_count += 1
        end
        puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        puts ""
      rescue StandardError => e
        puts "  結果: ❌ エラー発生: #{e.class} - #{e.message}"
        puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        puts ""
        Rails.logger.error("[reminders:send_event_reminders] Error: イベントID #{event.id} - #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
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
    puts "🏁 タスク完了: #{Time.zone.now.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    puts "=" * 80
    puts ""

    Rails.logger.info("[reminders:send_event_reminders] 完了 - 成功:#{sent_count}, 失敗:#{error_count}, スキップ:#{skipped_count}")
  end

  desc "タスクの72時間前LINEリマインドを送信"
  task send_task_reminders: :environment do
    puts ""
    puts "=" * 80
    puts "--- LINEリマインド判定開始（タスク） ---"
    puts "=" * 80

    # タイムゾーン情報を出力
    now = Time.zone.now
    puts "🕐 現在時刻（JST）: #{now.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    puts "🕐 現在時刻（UTC）: #{now.utc.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    puts "🌏 アプリケーションタイムゾーン: #{Time.zone.name}"
    puts ""

    # LINE認証情報が設定されているか確認
    unless LineBotService.credentials_configured?
      puts "⚠️ LINE認証情報が設定されていません。処理をスキップします。"
      Rails.logger.warn("[reminders:send_task_reminders] LINE認証情報が未設定")
      next
    end
    puts "✅ LINE認証情報: 設定済み"
    puts ""

    # まずデータベースの全タスク数を確認
    total_tasks = Task.count
    puts "📊 データベース内の全タスク数: #{total_tasks}件"

    # due_date が設定されているタスク数
    tasks_with_due = Task.where.not(due_date: nil).count
    puts "📊 期限設定されている全タスク数: #{tasks_with_due}件"

    # 未送信のタスク数
    tasks_not_sent = Task.where.not(due_date: nil).where(line_due_72h_notified_at: nil).count
    puts "📊 まだリマインド未送信のタスク数: #{tasks_not_sent}件"
    puts ""

    # リマインド対象のタスクを抽出
    # 条件:
    #   1. due_date が設定されている（nilではない）
    #   2. line_due_72h_notified_at が nil（まだ送信していない）
    #   3. due_date が現在時刻から72時間以内
    #   4. 完了していない（completed_at が nil）
    #   5. 非表示ではない
    #   6. LINE連携済みユーザー
    reminder_window_start = now
    reminder_window_end = now + 72.hours

    puts "🔍 検索条件:"
    puts "  1. due_date が nil でない"
    puts "  2. line_due_72h_notified_at が nil（未送信）"
    puts "  3. completed_at が nil（未完了）"
    puts "  4. hidden が false または nil"
    puts "  5. due_date が #{reminder_window_start.strftime('%Y-%m-%d %H:%M')} ～ #{reminder_window_end.strftime('%Y-%m-%d %H:%M')}"
    puts "  6. users.line_user_id が nil でない"
    puts ""

    tasks = Task
      .joins(character: :user)
      .where.not(due_date: nil)
      .where(line_due_72h_notified_at: nil)
      .where(completed_at: nil)
      .where("tasks.hidden IS NULL OR tasks.hidden = ?", false)
      .where("tasks.due_date BETWEEN ? AND ?", reminder_window_start, reminder_window_end)
      .where.not(users: { line_user_id: nil })

    puts "📊 リマインド対象候補数: #{tasks.count}件"
    puts ""

    if tasks.count > 0
      puts "📋 対象タスク一覧:"
      tasks.each do |task|
        hours_until_due = ((task.due_date - now) / 3600).round(1)
        puts "  - ID:#{task.id} 「#{task.title}」"
        puts "    期限: #{task.due_date.strftime('%Y-%m-%d %H:%M:%S %Z')}"
        puts "    期限まで: #{hours_until_due}時間"
        puts "    送信済みフラグ: #{task.line_due_72h_notified_at.present? ? task.line_due_72h_notified_at : 'nil（未送信）'}"
        puts "    完了状態: #{task.completed_at.present? ? '完了済み' : '未完了'}"
        puts "    ユーザーLINE ID: #{task.character&.user&.line_user_id || 'なし'}"
        puts ""
      end
    end

    Rails.logger.info("[reminders:send_task_reminders] 現在時刻: #{now}, 対象候補: #{tasks.count}件")

    sent_count = 0
    error_count = 0
    skipped_count = 0

    tasks.find_each do |task|
      begin
        user = task.character.user
        hours_until_due = ((task.due_date - now) / 3600).round(1)

        puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        puts "🔔 処理中: タスク「#{task.title}」(ID: #{task.id})"
        puts "  期限: #{task.due_date.strftime('%Y-%m-%d %H:%M:%S %Z')}"
        puts "  期限まで: #{hours_until_due}時間"
        puts "  現在時刻: #{now.strftime('%Y-%m-%d %H:%M:%S %Z')}"

        if user.line_user_id.blank?
          puts "  結果: ⏭️ スキップ（LINE未連携）"
          Rails.logger.warn("[reminders:send_task_reminders] スキップ: タスクID #{task.id} - LINE未連携")
          skipped_count += 1
          next
        end

        puts "  LINE送信先: #{user.line_user_id}"
        puts "  送信開始..."

        # LINEリマインドを送信
        service = LineBotService.new
        success = service.send_task_due_reminder(user.line_user_id, task)

        if success
          # 送信成功したら line_due_72h_notified_at を更新
          task.update_column(:line_due_72h_notified_at, now)
          puts "  結果: ✅ 送信成功！"
          Rails.logger.info("[reminders:send_task_reminders] 送信成功: タスクID #{task.id} → #{user.line_user_id}")
          sent_count += 1
        else
          puts "  結果: ❌ 送信失敗"
          Rails.logger.error("[reminders:send_task_reminders] 送信失敗: タスクID #{task.id}")
          error_count += 1
        end
        puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        puts ""
      rescue StandardError => e
        puts "  結果: ❌ エラー発生: #{e.class} - #{e.message}"
        puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        puts ""
        Rails.logger.error("[reminders:send_task_reminders] Error: タスクID #{task.id} - #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
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
    puts "🏁 タスク完了: #{Time.zone.now.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    puts "=" * 80
    puts ""

    Rails.logger.info("[reminders:send_task_reminders] 完了 - 成功:#{sent_count}, 失敗:#{error_count}, スキップ:#{skipped_count}")
  end

  desc "すべてのLINEリマインドを送信（イベント + タスク）"
  task send_all: :environment do
    puts ""
    puts "=" * 100
    puts "🚀 すべてのリマインド送信タスクを開始します"
    puts "=" * 100
    puts ""

    Rake::Task["reminders:send_event_reminders"].invoke
    puts ""
    Rake::Task["reminders:send_task_reminders"].invoke

    puts ""
    puts "=" * 100
    puts "🎉 すべてのリマインド送信タスクが完了しました"
    puts "=" * 100
    puts ""
  end

  # エイリアス: send_line は send_all と同じ
  desc "すべてのLINEリマインドを送信（send_allのエイリアス）"
  task send_line: :environment do
    Rake::Task["reminders:send_all"].invoke
  end

  # デバッグ用タスク
  desc "【デバッグ】リマインド送信フラグをリセット（テスト用）"
  task reset_flags: :environment do
    puts ""
    puts "=" * 80
    puts "⚠️ リマインド送信フラグをリセットします"
    puts "=" * 80
    puts ""

    # イベントのフラグをリセット
    events_count = Event.where.not(line_reminded_at: nil).count
    Event.where.not(line_reminded_at: nil).update_all(line_reminded_at: nil)
    puts "✅ イベントのリマインドフラグをリセット: #{events_count}件"

    # タスクのフラグをリセット
    tasks_count = Task.where.not(line_due_72h_notified_at: nil).count
    Task.where.not(line_due_72h_notified_at: nil).update_all(line_due_72h_notified_at: nil)
    puts "✅ タスクのリマインドフラグをリセット: #{tasks_count}件"

    puts ""
    puts "🎉 フラグリセット完了"
    puts ""
  end

  desc "【デバッグ】リマインド対象の状態を表示（送信なし）"
  task check_status: :environment do
    puts ""
    puts "=" * 80
    puts "📊 リマインド対象の状態確認"
    puts "=" * 80
    puts ""

    now = Time.zone.now
    puts "🕐 現在時刻（JST）: #{now.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    puts "🕐 現在時刻（UTC）: #{now.utc.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    puts "🌏 アプリケーションタイムゾーン: #{Time.zone.name}"
    puts ""

    # イベントの状態
    puts "━━━ イベント ━━━"
    total_events = Event.count
    events_with_reminder = Event.where.not(reminder_minutes: nil).count
    events_not_sent = Event.where.not(reminder_minutes: nil).where(line_reminded_at: nil).count
    events_sent = Event.where.not(reminder_minutes: nil).where.not(line_reminded_at: nil).count

    puts "  全イベント数: #{total_events}件"
    puts "  リマインド設定あり: #{events_with_reminder}件"
    puts "  └─ 未送信: #{events_not_sent}件"
    puts "  └─ 送信済み: #{events_sent}件"
    puts ""

    # 未送信イベントの詳細
    if events_not_sent > 0
      puts "  【未送信イベントの詳細】"
      Event.where.not(reminder_minutes: nil).where(line_reminded_at: nil).limit(10).each do |event|
        reminder_time = event.start_time - event.reminder_minutes.minutes
        time_diff = ((reminder_time - now) / 60).round
        status_text = now >= reminder_time ? "✅送信対象" : "⏰待機中（あと#{time_diff}分）"

        puts "    - ID:#{event.id} 「#{event.title}」"
        puts "      開始: #{event.start_time.strftime('%m/%d %H:%M')}"
        puts "      リマインド: #{event.reminder_minutes}分前 → #{reminder_time.strftime('%m/%d %H:%M')}"
        puts "      状態: #{status_text}"
        puts "      LINE ID: #{event.character&.user&.line_user_id || 'なし'}"
        puts ""
      end
    end

    # タスクの状態
    puts "━━━ タスク ━━━"
    total_tasks = Task.count
    tasks_with_due = Task.where.not(due_date: nil).count
    tasks_not_sent = Task.where.not(due_date: nil).where(line_due_72h_notified_at: nil).count
    tasks_sent = Task.where.not(due_date: nil).where.not(line_due_72h_notified_at: nil).count

    puts "  全タスク数: #{total_tasks}件"
    puts "  期限設定あり: #{tasks_with_due}件"
    puts "  └─ 未送信: #{tasks_not_sent}件"
    puts "  └─ 送信済み: #{tasks_sent}件"
    puts ""

    # 72時間以内のタスク
    reminder_window_end = now + 72.hours
    tasks_in_window = Task
      .where.not(due_date: nil)
      .where(line_due_72h_notified_at: nil)
      .where(completed_at: nil)
      .where("tasks.due_date BETWEEN ? AND ?", now, reminder_window_end)

    puts "  72時間以内の未完了タスク: #{tasks_in_window.count}件"

    if tasks_in_window.count > 0
      puts "  【72時間以内のタスク詳細】"
      tasks_in_window.limit(10).each do |task|
        hours_until_due = ((task.due_date - now) / 3600).round(1)

        puts "    - ID:#{task.id} 「#{task.title}」"
        puts "      期限: #{task.due_date.strftime('%m/%d %H:%M')}"
        puts "      残り: #{hours_until_due}時間"
        puts "      完了: #{task.completed_at.present? ? 'はい' : 'いいえ'}"
        puts "      LINE ID: #{task.character&.user&.line_user_id || 'なし'}"
        puts ""
      end
    end

    puts "=" * 80
    puts ""
  end
end
