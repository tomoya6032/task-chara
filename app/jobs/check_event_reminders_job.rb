# app/jobs/check_event_reminders_job.rb
# 毎分実行し、各イベントの reminder_minutes に応じたタイミングでLINEリマインドを送信するJob
class CheckEventRemindersJob < ApplicationJob
  queue_as :default

  # チェックウィンドウ（Jobが1分ごとに実行される想定でズレを吸収）
  WINDOW_SECONDS = 90

  def perform
    now = Time.current

    Rails.logger.info("[CheckEventRemindersJob] 実行開始 - 現在時刻: #{now.strftime('%Y-%m-%d %H:%M:%S %Z')}")

    # LINE認証情報が設定されているか確認
    unless LineBotService.credentials_configured?
      Rails.logger.warn("[CheckEventRemindersJob] LINE認証情報が未設定のため処理をスキップ")
      return
    end

    begin
      # リマインド対象のイベントを効率的に抽出
      # 条件:
      #   1. reminder_minutes が設定されている
      #   2. line_reminded_at が nil（未送信）
      #   3. start_time が未来（まだ開始していない）
      #   4. cancelled_at が nil（キャンセルされていない）
      #   5. LINE連携済みユーザー
      #   6. リマインド時刻が現在時刻の前後90秒以内

      # 各reminder_minutesに対してクエリを実行（効率化のため）
      [ 30, 60, 180, 1440, 4320 ].each do |minutes|
        target_time_start = now + minutes.minutes - WINDOW_SECONDS.seconds
        target_time_end = now + minutes.minutes + WINDOW_SECONDS.seconds

        events = Event
          .joins(character: :user)
          .where(reminder_minutes: minutes)
          .where(line_reminded_at: nil)
          .where("events.start_time BETWEEN ? AND ?", target_time_start, target_time_end)
          .where("events.start_time > ?", now)
          .where(cancelled_at: nil)
          .where.not(users: { line_user_id: nil })

        events.find_each do |event|
          begin
            # line_reminded_at を今すぐ更新して重複送信を防止
            event.update_column(:line_reminded_at, now)

            # 非同期ジョブをキュー
            SendLineReminderJob.perform_later(event.id)

            Rails.logger.info("[CheckEventRemindersJob] ✅ キュー登録: Event ID #{event.id} (#{event.title}) - #{event.reminder_minutes}分前")
          rescue => e
            Rails.logger.error("[CheckEventRemindersJob] ❌ Event ID #{event.id} のキュー登録エラー: #{e.class} - #{e.message}")
            Rails.logger.error(e.backtrace.first(3).join("\n"))
          end
        end

        if events.count > 0
          Rails.logger.info("[CheckEventRemindersJob] #{minutes}分前リマインド: #{events.count}件をキュー登録")
        end
      end

      Rails.logger.info("[CheckEventRemindersJob] 実行完了")

    rescue => e
      Rails.logger.error("[CheckEventRemindersJob] ❌ 予期しないエラー: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      raise # ジョブをリトライさせる
    end
  end
end
