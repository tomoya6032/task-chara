class SupportReport < ApplicationRecord
  belongs_to :character
  belongs_to :report_template, optional: true

  # ステータス定義
  enum :status, {
    draft: 0,      # 下書き
    generating: 1, # 生成中
    completed: 2,  # 完成
    error: 3       # エラー
  }

  validates :title, presence: true
  validates :period_start, :period_end, presence: true
  validate :period_end_after_start

  scope :recent, -> { order(created_at: :desc) }
  scope :by_period, ->(start_date, end_date) { where(period_start: start_date, period_end: end_date) }

  def period_activities
    character.activities.where(created_at: period_start.beginning_of_day..period_end.end_of_day)
  end

  def period_display
    "#{period_start.strftime('%Y年%m月%d日')} 〜 #{period_end.strftime('%Y年%m月%d日')}"
  end

  private

  def period_end_after_start
    return unless period_start && period_end

    if period_end <= period_start
      errors.add(:period_end, "終了日は開始日より後にしてください")
    end
  end
end
