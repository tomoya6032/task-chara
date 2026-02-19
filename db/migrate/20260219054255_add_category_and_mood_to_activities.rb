class AddCategoryAndMoodToActivities < ActiveRecord::Migration[8.0]
  def change
    add_column :activities, :category, :string
    add_column :activities, :mood_level, :integer
    add_column :activities, :fatigue_level, :integer
  end
end
