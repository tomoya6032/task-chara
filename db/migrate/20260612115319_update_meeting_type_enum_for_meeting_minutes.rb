class UpdateMeetingTypeEnumForMeetingMinutes < ActiveRecord::Migration[8.0]
  def up
    # 既存のmeeting_typeを削除して新しい定義に置き換え
    # 既存データは削除される（既存データがないことを確認済み）

    # 念のため既存データを削除
    execute "DELETE FROM meeting_minutes"

    # meeting_type列を削除
    remove_column :meeting_minutes, :meeting_type, :integer

    # 新しいmeeting_type列を追加
    # 0: regular_meeting (通常の会議議事録)
    # 1: medical_visit (診察同行の要約)
    add_column :meeting_minutes, :meeting_type, :integer, default: 0, null: false

    # インデックスを追加
    add_index :meeting_minutes, :meeting_type
  end

  def down
    # ロールバック処理
    remove_index :meeting_minutes, :meeting_type if index_exists?(:meeting_minutes, :meeting_type)
    remove_column :meeting_minutes, :meeting_type, :integer

    # 旧定義のmeeting_typeを復元
    # 0: support_meeting, 1: professional_meeting
    add_column :meeting_minutes, :meeting_type, :integer
  end
end
