# app/models/user.rb
class User < ApplicationRecord
  belongs_to :organization
  has_one :character, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # ユーザー作成時に自動でキャラクターを作成
  after_create :create_default_character

  private

  def create_default_character
    create_character(
      name: "#{email.split('@').first}のキャラクター",
      shave_level: 0,
      body_shape: 0,
      inner_peace: 0,
      intelligence: 0,
      toughness: 0
    )
  end
end
