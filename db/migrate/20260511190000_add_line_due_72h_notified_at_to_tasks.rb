class AddLineDue72hNotifiedAtToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :line_due_72h_notified_at, :datetime
    add_index :tasks, :line_due_72h_notified_at
  end
end
