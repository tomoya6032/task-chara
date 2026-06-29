# app/models/user.rb
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable, :lockable

  # ユーザーロールの定義
  enum :role, { individual: 0, enterprise_admin: 1, system_admin: 2 }, default: :individual

  # 関連付け
  belongs_to :organization, optional: true
  has_one :character, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :meeting_minutes, dependent: :destroy
  has_many :support_reports, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :ai_chats, dependent: :destroy
  has_many :ai_token_usages, dependent: :destroy

  # バリデーション
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validate :password_complexity

  # ユーザー作成時に自動でキャラクターを作成
  before_validation :set_default_name, on: :create
  after_create :create_default_character

  # エンタープライズ管理者は組織に所属している必要がある
  validates :organization_id, presence: true, if: :enterprise_admin?

  # トークン上限チェック
  def can_use_ai?
    return true if system_admin?

    if organization.present?
      organization.active? && !organization.token_limit_exceeded?
    else
      active?
    end
  end

  # 利用可能なユーザー（自分または配下のユーザー）
  def accessible_users
    if system_admin?
      User.all
    elsif enterprise_admin? && organization.present?
      organization.users
    else
      User.where(id: id)
    end
  end

  private

  def set_default_name
    self.name = email.split("@").first if name.blank?
  end

  def create_default_character
    create_character(
      name: "#{name || email.split('@').first}のキャラクター",
      shave_level: 0,
      body_shape: 0,
      inner_peace: 0,
      intelligence: 0,
      toughness: 0
    )
  end

  # パスワードの強度チェック
  def password_complexity
    return if password.blank? # パスワードが空の場合はスキップ（他のバリデーションが処理）

    # 8文字以上
    if password.length < 8
      errors.add :password, "は8文字以上で設定してください"
    end

    # 小文字を含む
    unless password.match?(/[a-z]/)
      errors.add :password, "には小文字を含めてください"
    end

    # 大文字を含む
    unless password.match?(/[A-Z]/)
      errors.add :password, "には大文字を含めてください"
    end

    # 数字を含む
    unless password.match?(/[0-9]/)
      errors.add :password, "には数字を含めてください"
    end

    # 記号を含む
    unless password.match?(/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/)
      errors.add :password, 'には記号(!@#$%等)を含めてください'
    end
  end
end
