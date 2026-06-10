class AddTokenFieldsToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :token_limit, :integer, default: 1000000, null: false # デフォルト100万トークン
    add_column :organizations, :token_used, :integer, default: 0, null: false
    add_column :organizations, :active, :boolean, default: true, null: false
  end
end
