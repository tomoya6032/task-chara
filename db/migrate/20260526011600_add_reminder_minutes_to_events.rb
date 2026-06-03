class AddReminderMinutesToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :reminder_minutes, :integer
  end
end
