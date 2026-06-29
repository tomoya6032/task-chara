# app/models/task.rb
class Task < ApplicationRecord
  belongs_to :character
  belongs_to :user, optional: true
  belongs_to :extracted_from_activity, class_name: "Activity", foreign_key: "extracted_from_activity_id", optional: true

  after_initialize :set_defaults
  after_save :manage_calendar_event
  before_save :reset_line_due_reminder_flag_if_needed

  validates :title, presence: true
  validates :category, presence: true
  validates :dislike_level, presence: true, numericality: { in: 1..10 }
  validates :extraction_confidence, numericality: { in: 0.0..1.0 }, allow_nil: true

  scope :completed, -> { where.not(completed_at: nil) }
  scope :pending, -> { where(completed_at: nil) }
  scope :visible, -> { where(hidden: false) }
  scope :hidden, -> { where(hidden: true) }
  scope :overdue, -> { pending.where("created_at < ?", 24.hours.ago) }
  scope :by_category, ->(category) { where(category: category) }
  scope :due_soon, -> { pending.where(due_date: Time.current..1.day.from_now) }
  scope :past_due, -> { pending.where("due_date < ?", Time.current) }
  scope :ordered_by_due_date, -> { order(Arel.sql("due_date IS NULL, due_date ASC")) }
  scope :ordered_by_created_date, -> { order(created_at: :desc) }

  # 抽出タスク関連のスコープ
  scope :draft, -> { where(is_draft: true) }
  scope :published, -> { where(is_draft: false) }
  scope :extracted, -> { where.not(extracted_from_activity_id: nil) }
  scope :manual, -> { where(extracted_from_activity_id: nil) }

  # タスク完了時の処理
  def mark_as_completed!
    update!(completed_at: Time.current)
    polish_character_from_completion
  end

  def completed?
    completed_at.present?
  end

  def overdue?
    return false if completed?
    created_at < 24.hours.ago
  end

  def due_date_passed?
    return false unless due_date.present?
    return false if completed?
    due_date < Time.current
  end

  def due_soon?
    return false unless due_date.present?
    return false if completed?
    due_date.between?(Time.current, 1.day.from_now)
  end

  def due_status
    return "完了" if completed?
    return "期限なし" unless due_date.present?

    if due_date_passed?
      "期限切れ"
    elsif due_soon?
      "期限間近"
    else
      "余裕あり"
    end
  end

  def due_date_display
    return "期限なし" unless due_date.present?
    due_date.strftime("%Y/%m/%d %H:%M")
  end

  def hide!
    if self.class.column_names.include?("hidden_at")
      update!(hidden: true, hidden_at: Time.current)
    else
      update!(hidden: true)
    end
  end

  def unhide!
    if self.class.column_names.include?("hidden_at")
      update!(hidden: false, hidden_at: nil)
    else
      update!(hidden: false)
    end
  end

  def category_display
    case category
    when "welfare"
      "訪問福祉 🏠"
    when "web"
      "Web制作 💻"
    when "admin"
      "事務作業 📋"
    when "personal"
      "個人"
    when "work"
      "仕事"
    when "meeting"
      "ミーティング"
    when "task_deadline"
      "タスク期限"
    else
      # カスタムカテゴリの名前を取得
      if character&.calendar_settings.present?
        settings = character.calendar_settings_hash
        cats = settings["custom_categories"]
        # インデックス付きハッシュを配列に変換
        cats = cats.values if cats.is_a?(Hash) && cats.keys.all? { |k| k.to_s =~ /^\d+$/ }
        if cats.is_a?(Array)
          custom_cat = cats.find { |c| c["id"] == category }
          return custom_cat["name"] if custom_cat
        end
      end
      category
    end
  end

  def dislike_level_display
    case dislike_level
    when 1..3
      "\u3084\u3084\u82E6\u624B \u{1F605}"
    when 4..6
      "\u82E6\u624B \u{1F630}"
    when 7..8
      "\u304B\u306A\u308A\u82E6\u624B \u{1F628}"
    when 9..10
      "\u5927\u5ACC\u3044 \u{1F631}"
    end
  end

  # カレンダーイベントとの同期
  def sync_calendar_event
    # ドラフト状態のタスクはカレンダーで同期しない
    if due_date.present? && !completed? && published?
      event = Event.find_or_initialize_by(external_id: task_external_id)
      # 時間が未指定（00:00）の場合は17:00-18:00をデフォルトにする
      effective_end = due_date.hour == 0 && due_date.min == 0 ? due_date.change(hour: 18) : due_date
      event.assign_attributes(
        title: "📋 #{title} (期限)",
        description: description.presence,
        start_time: effective_end - 1.hour,
        end_time: effective_end,
        all_day: false,
        event_type: "task_deadline",
        character: character
      )
      event.save!
    elsif due_date.blank? || completed?
      # 期限がなくなった、またはタスクが完了した場合、イベントを削除
      existing_event = Event.find_by(external_id: task_external_id)
      existing_event&.destroy
    end
  end

  def task_external_id
    "task_#{id}"
  end

  # 抽出タスク関連のメソッド
  def extracted?
    extracted_from_activity_id.present?
  end

  def draft?
    is_draft == true
  end

  def published?
    !draft?
  end

  def approve!
    update!(is_draft: false)
    sync_calendar_event if due_date.present?
  end

  def extraction_index
    return nil unless extracted?
    "AI-#{extracted_from_activity_id}-#{id}"
  end

  def extraction_confidence_display
    return "未設定" unless extraction_confidence.present?
    "#{(extraction_confidence * 100).round}%"
  end

  def source_activity
    extracted_from_activity
  end

  private

  def set_defaults
    self.hidden = false if hidden.nil?
    self.is_draft = false if is_draft.nil?
  end

  def manage_calendar_event
    sync_calendar_event if saved_change_to_due_date? || saved_change_to_title? || saved_change_to_completed_at? || saved_change_to_description?
  end

  def reset_line_due_reminder_flag_if_needed
    return unless self.class.column_names.include?("line_due_72h_notified_at")
    return unless will_save_change_to_due_date? || will_save_change_to_completed_at?

    self.line_due_72h_notified_at = nil
  end

  def polish_character_from_completion
    CharacterPolisher.new(character: character, task: self).polish_from_task_completion!
  end
end
