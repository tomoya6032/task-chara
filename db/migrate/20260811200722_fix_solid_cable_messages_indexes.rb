class FixSolidCableMessagesIndexes < ActiveRecord::Migration[8.0]
  def change
    # solid_cable_messages テーブルが存在する場合のみ処理
    if table_exists?(:solid_cable_messages)
      # id に対するユニークインデックスがない場合は追加 (Rails 8 の insert_all 対策)
      unless index_exists?(:solid_cable_messages, :id, unique: true)
        add_index :solid_cable_messages, :id, unique: true, if_not_exists: true
      end
    end
  end
end
