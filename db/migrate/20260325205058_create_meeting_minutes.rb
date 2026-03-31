class CreateMeetingMinutes < ActiveRecord::Migration[8.0]
  def change
    create_table :meeting_minutes do |t|
      t.string :title
      t.integer :meeting_type
      t.datetime :meeting_date
      t.text :content
      t.text :participants
      t.string :location
      t.references :character, null: false, foreign_key: true
      t.integer :status
      t.datetime :generated_at

      t.timestamps
    end

    add_index :meeting_minutes, [ :character_id, :meeting_date ]
    add_index :meeting_minutes, :meeting_type
    add_index :meeting_minutes, :status
  end
end
