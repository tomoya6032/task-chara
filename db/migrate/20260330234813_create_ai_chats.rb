class CreateAiChats < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_chats do |t|
      t.references :character, null: false, foreign_key: true
      t.string :conversation_id
      t.string :role
      t.text :content
      t.integer :tokens_used

      t.timestamps
    end
    add_index :ai_chats, :conversation_id
  end
end
