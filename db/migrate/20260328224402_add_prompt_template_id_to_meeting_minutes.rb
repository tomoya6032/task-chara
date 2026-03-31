class AddPromptTemplateIdToMeetingMinutes < ActiveRecord::Migration[8.0]
  def change
    add_reference :meeting_minutes, :prompt_template, null: true, foreign_key: true
  end
end
