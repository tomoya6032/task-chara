# app/models/activity.rb
require "base64"
require "uri"

class Activity < ApplicationRecord
  belongs_to :character

  validates :title, presence: true, length: { minimum: 2 }
  validates :content, presence: true, length: { minimum: 10 }

  scope :recent, -> { order(created_at: :desc) }
  scope :analyzed, -> { where.not(ai_analysis_log: {}) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }

  # 画像ファイルの仮想属性
  attr_accessor :image

  # 日報作成後の AI 解析実行
  after_create :analyze_and_polish_character

  # 画像処理のコールバック
  before_save :process_image_upload

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

  def has_image?
    image_url.present?
  end

  def image_data_url
    return nil unless has_image?

    if image_url.start_with?("data:")
      image_url
    elsif image_url =~ URI::DEFAULT_PARSER.make_regexp
      image_url
    else
      nil
    end
  end

  private

  def process_image_upload
    return unless image.present?

    if image.is_a?(ActionDispatch::Http::UploadedFile)
      # ファイルアップロードの場合、base64エンコードして保存
      begin
        # tempfile pathから直接読み取り
        file_path = image.tempfile.path
        file_content = File.binread(file_path)

        if file_content.empty?
          Rails.logger.error "File content is empty!"
          return
        end

        base64_data = Base64.strict_encode64(file_content)
        content_type = image.content_type || "image/jpeg"
        self.image_url = "data:#{content_type};base64,#{base64_data}"
      rescue => e
        Rails.logger.error "Error processing image upload: #{e.message}"
        nil
      end
    elsif image.is_a?(String) && image.start_with?("data:")
      # 既にbase64データの場合はそのまま保存
      self.image_url = image
    elsif image.is_a?(String) && image =~ URI::DEFAULT_PARSER.make_regexp
      # URLの場合はそのまま保存
      self.image_url = image
    end
  end

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
