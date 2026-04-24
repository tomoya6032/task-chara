class AddCalendarSettingsToCharacters < ActiveRecord::Migration[8.0]
  def change
    add_column :characters, :calendar_settings, :text
  end
end
