class AddExceptionFieldsToEvents < ActiveRecord::Migration[8.0]
  def change
    # 元の発生時刻（繰り返し予定の子イベント用）
    add_column :events, :original_start_time, :datetime

    # 個別変更フラグ（親から独立して編集されたか）
    add_column :events, :is_exception, :boolean, default: false, null: false

    # 論理削除タイムスタンプ（削除された日時）
    add_column :events, :cancelled_at, :datetime

    # インデックス追加（検索パフォーマンス向上）
    add_index :events, :cancelled_at
    add_index :events, :is_exception
    add_index :events, [ :recurring_event_id, :original_start_time ], name: 'index_events_on_recurring_and_original_start'

    # 既存の繰り返しイベントの子インスタンスに original_start_time を設定
    reversible do |dir|
      dir.up do
        # recurring_event_id が存在する子イベントに対して、original_start_time = start_time を設定
        execute <<-SQL
          UPDATE events
          SET original_start_time = start_time
          WHERE recurring_event_id IS NOT NULL
            AND original_start_time IS NULL;
        SQL
      end
    end
  end
end
