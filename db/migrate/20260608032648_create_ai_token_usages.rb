class CreateAiTokenUsages < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_token_usages do |t|
      t.references :user, null: false, foreign_key: true
      t.references :organization, null: true, foreign_key: true
      t.string :ai_model, null: false
      t.integer :prompt_tokens, default: 0, null: false
      t.integer :completion_tokens, default: 0, null: false
      t.integer :total_tokens, default: 0, null: false
      t.decimal :cost, precision: 10, scale: 6, default: 0.0
      t.string :feature # 'meeting_minutes', 'support_report', 'ai_chat'など

      t.timestamps
    end

    # パフォーマンス向上のためのインデックス
    add_index :ai_token_usages, [ :user_id, :created_at ]
    add_index :ai_token_usages, [ :organization_id, :created_at ]
    add_index :ai_token_usages, :feature
  end
end
