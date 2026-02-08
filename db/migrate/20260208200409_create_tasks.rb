class CreateTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :tasks do |t|
      t.references :character, null: false, foreign_key: true
      t.string :title, null: false
      t.string :category, null: false, default: 'admin'
      t.integer :dislike_level, default: 1, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :tasks, [ :character_id, :completed_at ]
    add_index :tasks, :category
  end
end
