class AddUserIdToMainModels < ActiveRecord::Migration[8.0]
  def change
    # 主要モデルにuser_idを追加（Characterは既にuser_idがあるため除外）
    # report_templatesも既にuser_idがあるため除外
    add_reference :activities, :user, foreign_key: true, null: true unless column_exists?(:activities, :user_id)
    add_reference :tasks, :user, foreign_key: true, null: true unless column_exists?(:tasks, :user_id)
    add_reference :meeting_minutes, :user, foreign_key: true, null: true unless column_exists?(:meeting_minutes, :user_id)
    add_reference :support_reports, :user, foreign_key: true, null: true unless column_exists?(:support_reports, :user_id)
    add_reference :events, :user, foreign_key: true, null: true unless column_exists?(:events, :user_id)
    add_reference :ai_chats, :user, foreign_key: true, null: true unless column_exists?(:ai_chats, :user_id)
    add_reference :prompt_templates, :user, foreign_key: true, null: true unless column_exists?(:prompt_templates, :user_id)
    # add_reference :report_templates, :user, foreign_key: true, null: true # 既に存在

    # インデックスを追加してパフォーマンスを向上
    add_index :activities, [ :user_id, :created_at ] unless index_exists?(:activities, [ :user_id, :created_at ])
    add_index :tasks, [ :user_id, :completed_at ] unless index_exists?(:tasks, [ :user_id, :completed_at ])
    add_index :meeting_minutes, [ :user_id, :meeting_date ] unless index_exists?(:meeting_minutes, [ :user_id, :meeting_date ])
    add_index :support_reports, [ :user_id, :created_at ] unless index_exists?(:support_reports, [ :user_id, :created_at ])
  end
end
