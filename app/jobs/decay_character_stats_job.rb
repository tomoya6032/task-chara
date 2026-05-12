class DecayCharacterStatsJob < ApplicationJob
  queue_as :default

  DECAY_AMOUNT = 1
  STAT_COLUMNS = %w[inner_peace intelligence toughness shave_level body_shape].freeze

  def perform
    Character.find_each do |character|
      updates = STAT_COLUMNS.each_with_object({}) do |stat, hash|
        current = character.public_send(stat) || 0
        hash[stat] = [ current - DECAY_AMOUNT, 0 ].max
      end
      character.update_columns(updates)
    end
  end
end
