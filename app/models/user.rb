# app/models/user.rb
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

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
end
