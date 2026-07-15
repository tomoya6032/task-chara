class AddLineRemindedAtToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :line_reminded_at, :datetime
    add_index :events, :line_reminded_at
  end
end
