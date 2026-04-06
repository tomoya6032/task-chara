class AiChat < ApplicationRecord
  belongs_to :character

  # Role validation
  validates :role, presence: true, inclusion: { in: %w[user assistant system] }
  validates :content, presence: true
  validates :conversation_id, presence: true

  # Scopes
  scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id) }
  scope :recent, -> { order(:created_at) }
  scope :by_role, ->(role) { where(role: role) }

  # Generate unique conversation ID
  def self.generate_conversation_id
    SecureRandom.uuid
  end

  # Get conversation summary for context
  def self.conversation_context(conversation_id, limit = 10)
    for_conversation(conversation_id)
      .recent
      .limit(limit)
      .pluck(:role, :content)
      .map { |role, content| { role: role, content: content } }
  end
end
