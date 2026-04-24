class AddExtractedFieldsToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :is_draft, :boolean
    add_column :tasks, :extracted_from_activity_id, :integer
    add_column :tasks, :extraction_confidence, :decimal
    add_column :tasks, :extraction_source_text, :text
  end
end
