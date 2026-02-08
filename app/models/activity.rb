# app/models/activity.rb
class Activity < ApplicationRecord
  belongs_to :character

  validates :content, presence: true, length: { minimum: 10 }

  scope :recent, -> { order(created_at: :desc) }
  scope :analyzed, -> { where.not(ai_analysis_log: {}) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }

  # 日報作成後の AI 解析実行
  after_create :analyze_and_polish_character

  def analysis_completed?
    ai_analysis_log.present? && ai_analysis_log["analysis_result"].present?
  end

  def analysis_result
    ai_analysis_log["analysis_result"] if analysis_completed?
  end

  def bonuses_applied
    ai_analysis_log["bonuses_applied"] if analysis_completed?
  end

  def analysis_comment
    analysis_result&.dig("analysis_comment") || "\u307E\u3060\u89E3\u6790\u3055\u308C\u3066\u3044\u307E\u305B\u3093"
  end

  # ステータス向上度の表示用
  def status_improvements
    return {} unless bonuses_applied

    {
      intelligence: bonuses_applied["intelligence"]&.round(1) || 0,
      inner_peace: bonuses_applied["inner_peace"]&.round(1) || 0,
      toughness: bonuses_applied["toughness"]&.round(1) || 0
    }
  end

  def content_summary(length: 100)
    return content if content.length <= length
    "#{content[0..length]}..."
  end

  private

  def analyze_and_polish_character
    # バックグラウンドジョブで実行することも考慮
    AnalyzeActivityJob.perform_later(self) if defined?(AnalyzeActivityJob)

    # 同期実行版（開発用）
    perform_analysis unless Rails.env.production?
  end

  def perform_analysis
    CharacterPolisher.new(character: character, activity: self).polish_from_activity!
  end
end
