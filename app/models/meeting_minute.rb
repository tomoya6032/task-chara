class MeetingMinute < ApplicationRecord
  belongs_to :character
  belongs_to :user, optional: true
  belongs_to :prompt_template, optional: true

  # 会議タイプ定義
  enum :meeting_type, {
    regular_meeting: 0,    # 通常の会議議事録
    medical_visit: 1       # 診察同行の要約
  }

  # ステータス定義
  enum :status, {
    draft: 0,      # 下書き
    generating: 1, # 生成中
    completed: 2,  # 完成
    error: 3       # エラー
  }

  validates :title, presence: true, length: { maximum: 200 }
  validates :meeting_date, presence: true
  validates :meeting_type, presence: true

  scope :recent, -> { order(meeting_date: :desc) }
  scope :by_type, ->(type) { where(meeting_type: type) }

  def meeting_type_display
    case meeting_type
    when "regular_meeting"
      "通常の会議議事録"
    when "medical_visit"
      "診察同行の要約"
    else
      "不明"
    end
  end

  def formatted_meeting_date
    meeting_date&.strftime("%Y\u5E74%m\u6708%d\u65E5 %H:%M")
  end
end
