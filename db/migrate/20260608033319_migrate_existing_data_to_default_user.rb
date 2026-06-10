class MigrateExistingDataToDefaultUser < ActiveRecord::Migration[8.0]
  def up
    # デフォルトユーザーを作成
    password = SecureRandom.hex(16)
    default_user = User.create!(
      email: 'default@task-character.local',
      name: 'デフォルトユーザー',
      password: password,
      password_confirmation: password,
      role: :individual,
      active: true
    )

    puts "Created default user: #{default_user.email}"

    # 既存のキャラクターをデフォルトユーザーに紐付け
    Character.where(user_id: nil).update_all(user_id: default_user.id)
    puts "Associated #{Character.where(user_id: default_user.id).count} characters with default user"

    # 各キャラクターのデータをユーザーに紐付け
    Character.where(user_id: default_user.id).find_each do |character|
      Activity.where(character_id: character.id, user_id: nil).update_all(user_id: default_user.id)
      Task.where(character_id: character.id, user_id: nil).update_all(user_id: default_user.id)
      MeetingMinute.where(character_id: character.id, user_id: nil).update_all(user_id: default_user.id)
      SupportReport.where(character_id: character.id, user_id: nil).update_all(user_id: default_user.id)
      Event.where(character_id: character.id, user_id: nil).update_all(user_id: default_user.id)
      AiChat.where(character_id: character.id, user_id: nil).update_all(user_id: default_user.id)
    end

    puts "Migrated existing data to default user"
  end

  def down
    # ロールバック時は何もしない（既存データを保持）
    puts "Rollback: Keeping existing data associations"
  end
end
