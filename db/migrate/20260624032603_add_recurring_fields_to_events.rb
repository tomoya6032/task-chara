class AddRecurringFieldsToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :recurring, :boolean, default: false, null: false
    add_column :events, :recurring_event_id, :bigint
    add_column :events, :recurrence_end_date, :date
    add_column :events, :recurrence_count, :integer

    add_index :events, :recurring
    add_index :events, :recurring_event_id
    add_foreign_key :events, :events, column: :recurring_event_id
  end
end
