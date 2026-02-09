class AddHiddenAtToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :hidden_at, :datetime
  end
end
