class AddHiddenToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :hidden, :boolean, default: false, null: false
  end
end
