class AddVisitFieldsToActivities < ActiveRecord::Migration[8.0]
  def change
    add_column :activities, :title, :string
    add_column :activities, :visit_start_time, :datetime
    add_column :activities, :visit_end_time, :datetime
  end
end
