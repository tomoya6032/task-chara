class MeetingMinute < ApplicationRecord
  belongs_to :character
  belongs_to :prompt_template, optional: true

  # 会議タイプ定義
  enum :meeting_type, {
    support_meeting: 0,    # 利用者支援会議
    professional_meeting: 1 # 専門職団体会議
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
    when "support_meeting"
      "\u5229\u7528\u8005\u652F\u63F4\u4F1A\u8B70"
    when "professional_meeting"
      "\u5C02\u9580\u8077\u56E3\u4F53\u4F1A\u8B70"
    else
      "\u4E0D\u660E"
    end
  end

  def formatted_meeting_date
    meeting_date&.strftime("%Y\u5E74%m\u6708%d\u65E5 %H:%M")
  end
end
