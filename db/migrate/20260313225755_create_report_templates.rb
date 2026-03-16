class CreateReportTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :report_templates do |t|
      t.string :name, null: false
      t.text :description
      t.text :format_instructions
      t.boolean :is_default, default: false
      t.references :user, null: true, foreign_key: true
      t.string :pdf_file_name
      t.integer :pdf_file_size

      t.timestamps
    end
    
    add_index :report_templates, :is_default, if_not_exists: true
  end
end
