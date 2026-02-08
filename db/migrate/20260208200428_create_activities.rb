class CreateActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :activities do |t|
      t.references :character, null: false, foreign_key: true
      t.text :content, null: false
      t.string :image_url
      t.jsonb :ai_analysis_log, default: {}

      t.timestamps
    end

    add_index :activities, :character_id
    add_index :activities, :created_at
    add_index :activities, :ai_analysis_log, using: :gin
  end
end
