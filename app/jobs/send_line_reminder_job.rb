# app/jobs/send_line_reminder_job.rb
# 特定のイベントに対してLINEリマインドを送信するJob
class SendLineReminderJob < ApplicationJob
  queue_as :default

  # リトライ設定: 最大3回、指数バックオフ
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # @param event_id [Integer] リマインド対象のEvent ID
  def perform(event_id)
    event = Event.includes(character: :user).find_by(id: event_id)
    unless event
      Rails.logger.warn("[SendLineReminderJob] ⚠️ Event #{event_id} が見つかりません。スキップ。")
      return
    end

    line_user_id = event.character&.user&.line_user_id
    unless line_user_id.present?
      Rails.logger.info("[SendLineReminderJob] ⚠️ Event #{event_id} のユーザーにline_user_idがありません。スキップ。")
      return
    end

    # 既に送信済みかチェック
    if event.line_reminded_at.present?
      Rails.logger.info("[SendLineReminderJob] ℹ️ Event #{event_id} は既に送信済み (#{event.line_reminded_at})。スキップ。")
      return
    end

    begin
      Rails.logger.info("[SendLineReminderJob] 📤 送信開始: Event #{event_id} (#{event.title}) → #{line_user_id}")

      service = LineBotService.new
      success = service.send_event_reminder(line_user_id, event)

      if success
        # 送信成功時はline_reminded_atを更新（二重送信防止）
        event.update_column(:line_reminded_at, Time.current) unless event.line_reminded_at.present?
        Rails.logger.info("[SendLineReminderJob] ✅ 送信成功: Event #{event_id} → #{line_user_id}")
      else
        Rails.logger.error("[SendLineReminderJob] ❌ 送信失敗: Event #{event_id} - LINE API がfalseを返しました")
        # 失敗時は例外を発生させてリトライ
        raise "LINE API returned false for event #{event_id}"
      end

    rescue => e
      Rails.logger.error("[SendLineReminderJob] ❌ 送信エラー: Event #{event_id} - #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(3).join("\n"))
      raise # リトライを発動
    end
  end
end
