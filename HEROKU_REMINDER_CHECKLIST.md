# LINEリマインド 緊急チェックリスト（Heroku環境）

本番環境でLINEリマインドが送信されない場合、以下を順番に確認してください。

## ⚡ 1分で確認（最重要項目）

### 1. Workerプロセスが起動しているか
```bash
heroku ps
```

**正常な場合:**
```
=== worker (Hobby): bundle exec rake solid_queue:start (1)
worker.1: up 2024/01/01 12:00:00 +0900
```

**異常な場合（workerが表示されない）:**
```bash
heroku ps:scale worker=1
```

### 2. LINE認証情報が設定されているか
```bash
heroku config:get LINE_CHANNEL_SECRET
heroku config:get LINE_CHANNEL_TOKEN
```

**未設定の場合:**
```bash
heroku config:set LINE_CHANNEL_SECRET="あなたのシークレット"
heroku config:set LINE_CHANNEL_TOKEN="あなたのトークン"
heroku ps:restart worker
```

### 3. ジョブが実行されているか（ログ確認）
```bash
heroku logs --tail --ps worker | grep "CheckEventRemindersJob"
```

1分待って何もログが出ない場合、ジョブが動いていない可能性があります。

## 📋 詳細確認（5分）

### 4. タイムゾーン設定
```bash
heroku config:get TZ
```

**未設定または UTC の場合:**
```bash
heroku config:set TZ="Asia/Tokyo"
heroku ps:restart worker
```

### 5. ジョブの登録確認
```bash
heroku run bash
```

**Heroku Console内で:**
```ruby
# Solid Queueの設定を確認
SolidQueue::RecurringTask.all.pluck(:key, :schedule)

# 期待される出力:
# [
#   ["check_event_reminders", "every minute"],
#   ["check_task_due_reminders", "every minute"],
#   ...
# ]
```

### 6. 対象イベント・タスクの存在確認
```bash
heroku run bash
```

**Heroku Console内で:**
```ruby
# リマインド対象のイベント数
Event.joins(character: :user)
     .where.not(reminder_minutes: nil)
     .where(line_reminded_at: nil)
     .where('events.start_time > ?', Time.current)
     .where(cancelled_at: nil)
     .where.not(users: { line_user_id: nil })
     .count

# 結果が 0 の場合、対象イベントがない（正常）
# 結果が 1以上の場合、送信されるべきイベントがある

# 最近のイベントの詳細
Event.where.not(reminder_minutes: nil)
     .where(line_reminded_at: nil)
     .order(:start_time)
     .limit(3)
     .each do |e|
  remind_at = e.start_time - e.reminder_minutes.minutes
  puts "ID:#{e.id} #{e.title}"
  puts "  開始: #{e.start_time.strftime('%Y-%m-%d %H:%M %Z')}"
  puts "  送信予定: #{remind_at.strftime('%Y-%m-%d %H:%M %Z')}"
  puts "  LINE ID: #{e.character&.user&.line_user_id || 'なし'}"
  puts ""
end
```

## 🧪 手動テスト（10分）

### 7. テストイベントで送信確認
```bash
heroku run bash
```

**Heroku Console内で:**
```ruby
# テスト用イベントを作成（5分後に開始）
user = User.where.not(line_user_id: nil).first
character = user.characters.first

test_event = Event.create!(
  title: "【テスト】リマインド確認",
  start_time: 5.minutes.from_now,
  end_time: 6.minutes.from_now,
  reminder_minutes: 30,  # テストのため30分前に設定（本来なら今すぐ送信されるはず）
  event_type: "other",
  character: character
)

puts "テストイベント作成: ID #{test_event.id}"

# 即座に送信テスト
service = LineBotService.new
result = service.send_event_reminder(user.line_user_id, test_event)

if result
  puts "✅ 送信成功！LINEアプリを確認してください"
  test_event.update_column(:line_reminded_at, Time.current)
else
  puts "❌ 送信失敗。LINE APIの設定を確認してください"
end

# テスト後削除
test_event.destroy
```

### 8. ジョブを手動実行
```bash
heroku run bin/rails reminders:test:run_event_job
```

ログに「✅ キュー登録」が表示されれば正常です。

## 🔍 トラブルシューティング

### ケース1: 「LINE認証情報が未設定」エラー
```bash
# 環境変数を確認
heroku config | grep LINE

# 設定
heroku config:set LINE_CHANNEL_SECRET="..."
heroku config:set LINE_CHANNEL_TOKEN="..."

# Worker再起動
heroku ps:restart worker
```

### ケース2: 「送信済みなのに届かない」
- ユーザーがBotをブロックしている可能性
- LINE Developer Consoleでメッセージ配信数を確認
- Herokuログで「✅ 送信成功」が出ているか確認

### ケース3: 「ジョブが実行されない」
```bash
# Workerを再起動
heroku ps:restart worker

# ログでジョブの実行を確認（1分待つ）
heroku logs --tail --ps worker
```

### ケース4: 「重複送信される」
フラグ管理の修正により解消されているはずです。
それでも発生する場合:
```bash
heroku run bash
```
```ruby
# 重複送信されたイベントを確認
Event.where.not(line_reminded_at: nil)
     .order(line_reminded_at: :desc)
     .limit(10)
     .pluck(:id, :title, :line_reminded_at)
```

## 📞 確認コマンド一覧（コピペ用）

```bash
# 1. Worker起動確認
heroku ps

# 2. LINE認証情報確認
heroku config | grep LINE

# 3. ログ確認（リアルタイム）
heroku logs --tail --ps worker

# 4. タイムゾーン確認
heroku config:get TZ

# 5. テストタスク実行
heroku run bin/rails reminders:test:list_events

# 6. 手動送信テスト（Event ID 123 の場合）
heroku run bin/rails 'reminders:test:send_event[123]'

# 7. Console起動
heroku run bash
```

## ✅ 正常動作の確認方法

1. **Worker起動**: `heroku ps` で `worker.1: up` と表示される
2. **認証情報**: `heroku config | grep LINE` で2つの環境変数が表示される
3. **ジョブ実行**: ログに毎分「CheckEventRemindersJob 実行開始」が表示される
4. **送信成功**: イベント時刻の30分前にLINEメッセージが届く

## 🚨 緊急時の連絡先

修正内容の詳細は [LINE_REMINDER_FIX_REPORT.md](LINE_REMINDER_FIX_REPORT.md) を参照してください。
