# app/models/organization.rb
class Organization < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :characters, through: :users
  has_many :ai_token_usages, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :token_limit, presence: true, numericality: { greater_than: 0 }

  # トークン上限を超えているかチェック
  def token_limit_exceeded?
    token_used >= token_limit
  end

  # トークン使用率（パーセント）
  def token_usage_percentage
    return 0 if token_limit.zero?
    ((token_used.to_f / token_limit) * 100).round(2)
  end

  # 残りトークン数
  def remaining_tokens
    [ token_limit - token_used, 0 ].max
  end

  # トークン使用量を更新
  def add_token_usage(tokens)
    increment!(:token_used, tokens)
  end

  # エンタープライズ管理者を取得
  def admins
    users.where(role: :enterprise_admin)
  end

  # 個人ユーザーを取得
  def members
    users.where(role: :individual)
  end
end
