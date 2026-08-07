class AddMonthlyRecurrenceOptionsToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :monthly_recurrence_type, :string
    add_column :events, :monthly_day, :integer
    add_column :events, :monthly_week, :integer
    add_column :events, :monthly_day_of_week, :integer
  end
end
