class ChangeEventTypeToStringInEvents < ActiveRecord::Migration[8.0]
  def up
    # 既存のinteger値をstringに変換
    # personal: 0, work: 1, meeting: 2, task_deadline: 3, google_sync: 4, apple_sync: 5
    mapping = {
      0 => 'personal',
      1 => 'work',
      2 => 'meeting',
      3 => 'task_deadline',
      4 => 'google_sync',
      5 => 'apple_sync'
    }

    # 一時カラムを作成
    add_column :events, :event_type_string, :string

    # 既存データを変換
    Event.reset_column_information
    Event.find_each do |event|
      event.update_columns(event_type_string: mapping[event.event_type])
    end

    # 古いカラムを削除し、新しいカラムをリネーム
    remove_column :events, :event_type
    rename_column :events, :event_type_string, :event_type

    # インデックスを再作成
    add_index :events, :event_type
  end

  def down
    # 逆操作：stringからintegerに戻す
    reverse_mapping = {
      'personal' => 0,
      'work' => 1,
      'meeting' => 2,
      'task_deadline' => 3,
      'google_sync' => 4,
      'apple_sync' => 5
    }

    # 一時カラムを作成
    add_column :events, :event_type_integer, :integer

    # データを変換
    Event.reset_column_information
    Event.find_each do |event|
      event.update_columns(event_type_integer: reverse_mapping[event.event_type] || 0)
    end

    # カラムを入れ替え
    remove_column :events, :event_type
    rename_column :events, :event_type_integer, :event_type

    # インデックスを再作成
    add_index :events, :event_type
  end
end
