class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.string :title, null: false
      t.text :description
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.string :location
      t.boolean :all_day, default: false
      t.integer :event_type, default: 0
      t.integer :status, default: 0
      t.string :external_id
      t.string :external_calendar_id
      t.string :google_event_id
      t.string :apple_event_id
      t.text :attendees
      t.string :color
      t.text :recurrence_rule
      t.references :character, null: true, foreign_key: true
      t.json :metadata

      t.timestamps
    end

    add_index :events, :start_time
    add_index :events, :end_time
    add_index :events, [ :start_time, :end_time ]
    add_index :events, :event_type
    add_index :events, :external_id, unique: true
    add_index :events, :character_id, name: 'index_events_on_character_id_new'
  end
end
