# app/models/organization.rb
class Organization < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :characters, through: :users

  validates :name, presence: true, uniqueness: true
end
