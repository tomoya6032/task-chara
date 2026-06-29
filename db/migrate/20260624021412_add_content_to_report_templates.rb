class AddContentToReportTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column :report_templates, :content, :text
  end
end
