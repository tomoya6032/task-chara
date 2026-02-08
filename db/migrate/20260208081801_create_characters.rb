class CreateCharacters < ActiveRecord::Migration[8.0]
  def change
    create_table :characters do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :shave_level, default: 0, null: false
      t.integer :body_shape, default: 0, null: false
      t.integer :inner_peace, default: 0, null: false
      t.integer :intelligence, default: 0, null: false
      t.integer :toughness, default: 0, null: false

      t.timestamps
    end
  end
end
