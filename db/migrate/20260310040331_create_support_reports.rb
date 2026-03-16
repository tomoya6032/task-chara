class CreateSupportReports < ActiveRecord::Migration[8.0]
  def change
    create_table :support_reports do |t|
      t.references :character, null: false, foreign_key: true
      t.string :title
      t.date :period_start
      t.date :period_end
      t.text :content
      t.datetime :generated_at
      t.integer :status

      t.timestamps
    end
  end
end
