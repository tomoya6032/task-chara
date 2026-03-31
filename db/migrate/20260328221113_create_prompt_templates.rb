class CreatePromptTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :prompt_templates do |t|
      t.string :name, null: false
      t.integer :meeting_type, null: false
      t.integer :prompt_type, null: false
      t.text :system_prompt, null: false
      t.text :user_prompt_template, null: false
      t.boolean :is_active, default: true, null: false
      t.integer :organization_id
      t.text :description

      t.timestamps
    end

    add_index :prompt_templates, [ :meeting_type, :prompt_type, :is_active ]
    add_index :prompt_templates, :organization_id
    add_index :prompt_templates, :is_active
  end
end
