# app/models/task.rb
class Task < ApplicationRecord
  belongs_to :character

  after_initialize :set_defaults

  validates :title, presence: true
  validates :category, presence: true, inclusion: { in: %w[welfare web admin] }
  validates :dislike_level, presence: true, numericality: { in: 1..10 }

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
      "\u8A2A\u554F\u798F\u7949 \u{1F3E0}"
    when "web"
      "Web\u5236\u4F5C \u{1F4BB}"
    when "admin"
      "\u4E8B\u52D9\u4F5C\u696D \u{1F4CB}"
    else
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

  private

  def set_defaults
    self.hidden = false if hidden.nil?
  end

  def polish_character_from_completion
    CharacterPolisher.new(character: character, task: self).polish_from_task_completion!
  end
end
