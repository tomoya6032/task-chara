class UpdatePromptTemplateMeetingTypeEnum < ActiveRecord::Migration[8.0]
  def up
    # 既存のprompt_templatesを削除して新しい定義に置き換え
    # 既存データは削除される（既存データがないことを確認済み）

    # 念のため既存データを削除
    execute "DELETE FROM prompt_templates"

    # meeting_type列を削除
    remove_column :prompt_templates, :meeting_type, :integer

    # 新しいmeeting_type列を追加
    # 0: regular_meeting (通常の会議議事録)
    # 1: medical_visit (診察同行の要約)
    # 2: general (汎用)
    add_column :prompt_templates, :meeting_type, :integer, default: 2, null: false

    # インデックスを追加
    add_index :prompt_templates, :meeting_type
  end

  def down
    # ロールバック処理
    remove_index :prompt_templates, :meeting_type if index_exists?(:prompt_templates, :meeting_type)
    remove_column :prompt_templates, :meeting_type, :integer

    # 旧定義のmeeting_typeを復元
    # 0: support_meeting, 1: professional_meeting, 2: general
    add_column :prompt_templates, :meeting_type, :integer
  end
end
