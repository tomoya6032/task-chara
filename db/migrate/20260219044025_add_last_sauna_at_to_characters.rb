class AddLastSaunaAtToCharacters < ActiveRecord::Migration[8.0]
  def change
    add_column :characters, :last_sauna_at, :datetime
  end
end
