class AiTokenUsage < ApplicationRecord
  belongs_to :user
  belongs_to :organization, optional: true

  validates :ai_model, presence: true
  validates :total_tokens, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # トークン数を計算
  before_validation :calculate_total_tokens

  # 組織のトークン使用量を更新
  after_create :update_organization_usage

  # スコープ
  scope :for_feature, ->(feature) { where(feature: feature) }
  scope :recent, -> { order(created_at: :desc) }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..Time.current.end_of_month) }

  private

  def calculate_total_tokens
    self.total_tokens = (prompt_tokens || 0) + (completion_tokens || 0)
  end

  def update_organization_usage
    organization&.add_token_usage(total_tokens)
  end
end
