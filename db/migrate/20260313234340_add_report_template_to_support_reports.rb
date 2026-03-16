class AddReportTemplateToSupportReports < ActiveRecord::Migration[8.0]
  def change
    add_reference :support_reports, :report_template, null: true, foreign_key: true, index: true
  end
end
