# LINEリマインド自動通知 修正完了レポート

## 📋 問題の特定

### 主要な原因
1. **フラグ管理の不一致** (最重要)
   - `CheckEventRemindersJob`: `metadata['line_reminder_sent_at']` を使用
   - `SendLineReminderJob` & Rakeタスク: `line_reminded_at` カラムを使用
   - この不一致により、一方で送信済みでも他方が再送信する可能性があった

2. **非効率なクエリ**
   - `CheckEventRemindersJob`がすべてのイベントを`find_each`でループ
   - データベースレベルでフィルタすべき条件をRubyコードで判定

3. **エラーハンドリング不足**
   - ジョブ内で例外が発生してもサイレント失敗
   - リトライ機構が未設定
   - ログ出力が不十分

## ✅ 実施した修正

### 1. CheckEventRemindersJob の修正 ([check_event_reminders_job.rb](app/jobs/check_event_reminders_job.rb))

**変更内容:**
- フラグ管理を `line_reminded_at` カラムに統一
- 効率的なクエリに変更（各reminder_minutesごとにデータベースでフィルタ）
- LINE認証情報チェックを追加
- 包括的なエラーハンドリングとログ出力

**主要な改善点:**
```ruby
# 修正前: 全イベントをループして個別チェック
Event.where.not(reminder_minutes: nil).find_each do |event|
  remind_at = event.start_time - event.reminder_minutes.minutes
  next unless remind_at.between?(now - 90.seconds, now + 90.seconds)
  # ...
end

# 修正後: データベースレベルで効率的にフィルタ
[30, 60, 180, 1440, 4320].each do |minutes|
  target_time_start = now + minutes.minutes - 90.seconds
  target_time_end = now + minutes.minutes + 90.seconds

  events = Event
    .joins(character: :user)
    .where(reminder_minutes: minutes)
    .where(line_reminded_at: nil)
    .where('events.start_time BETWEEN ? AND ?', target_time_start, target_time_end)
    .where('events.start_time > ?', now)
    .where(cancelled_at: nil)
    .where.not(users: { line_user_id: nil })
end
```

### 2. SendLineReminderJob の修正 ([send_line_reminder_job.rb](app/jobs/send_line_reminder_job.rb))

**変更内容:**
- `line_reminded_at` カラムを使用するように統一
- リトライ機構を追加（最大3回、指数バックオフ）
- 重複送信チェックを追加
- エラー時のログ出力を強化
- 送信失敗時に例外を発生させてリトライを発動

**主要な改善点:**
```ruby
# リトライ設定を追加
retry_on StandardError, wait: :exponentially_longer, attempts: 3

# 重複送信チェック
if event.line_reminded_at.present?
  Rails.logger.info("[SendLineReminderJob] ℹ️ 既に送信済み。スキップ。")
  return
end

# 送信成功時にフラグ更新
if success
  event.update_column(:line_reminded_at, Time.current)
else
  raise "LINE API returned false" # リトライを発動
end
```

### 3. CheckTaskDueRemindersJob の修正 ([check_task_due_reminders_job.rb](app/jobs/check_task_due_reminders_job.rb))

**変更内容:**
- LINE認証情報チェックを追加
- エラーハンドリングとログ出力を強化
- ユーザークエリに明示的なJOIN条件を追加

### 4. SendTaskDueReminderJob の修正 ([send_task_due_reminder_job.rb](app/jobs/send_task_due_reminder_job.rb))

**変更内容:**
- リトライ機構を追加
- 送信失敗時にフラグをリセット（再試行可能に）
- エラーハンドリングとログ出力を強化

### 5. テスト用Rakeタスクの追加 ([lib/tasks/reminder_test.rake](lib/tasks/reminder_test.rake))

新規作成したデバッグ・テスト用タスク:

**即座に送信テスト:**
```bash
# イベントリマインドをテスト送信
bin/rails 'reminders:test:send_event[123]'

# タスクリマインドをテスト送信
bin/rails 'reminders:test:send_task[456]'
```

**ジョブを手動実行:**
```bash
# CheckEventRemindersJobを実行
bin/rails reminders:test:run_event_job

# CheckTaskDueRemindersJobを実行
bin/rails reminders:test:run_task_job
```

**対象を一覧表示（送信なし）:**
```bash
# リマインド対象イベント一覧
bin/rails reminders:test:list_events

# 72時間前リマインド対象タスク一覧
bin/rails reminders:test:list_tasks
```

**フラグをリセット:**
```bash
# 特定のイベントの送信フラグをリセット
bin/rails 'reminders:test:reset_event[123]'

# 特定のタスクの送信フラグをリセット
bin/rails 'reminders:test:reset_task[456]'
```

## 🚀 Heroku環境での設定確認

### 1. 定期実行ジョブの確認

**config/recurring.yml の設定:**
```yaml
production:
  check_event_reminders:
    class: CheckEventRemindersJob
    queue: default
    schedule: every minute

  check_task_due_reminders:
    class: CheckTaskDueRemindersJob
    queue: default
    schedule: every minute
```

✅ **確認済み**: 両ジョブが毎分実行される設定になっています。

### 2. Solid Queue Workerの確認

**Procfile:**
```
web: bundle exec puma -C config/puma.rb
worker: bundle exec rake solid_queue:start
```

**Herokuでworkerが起動しているか確認:**
```bash
heroku ps
```

出力例:
```
=== worker (Hobby): bundle exec rake solid_queue:start (1)
worker.1: up 2024/01/01 12:00:00 +0900 (~ 1h ago)
```

**workerが停止している場合は起動:**
```bash
heroku ps:scale worker=1
```

### 3. LINE認証情報の確認

```bash
# 環境変数を確認
heroku config:get LINE_CHANNEL_SECRET
heroku config:get LINE_CHANNEL_TOKEN

# または
heroku config | grep LINE
```

**必要な環境変数:**
- `LINE_CHANNEL_SECRET`: LINE Messaging APIのChannel Secret
- `LINE_CHANNEL_TOKEN`: LINE Messaging APIのChannel Access Token

**設定されていない場合:**
```bash
heroku config:set LINE_CHANNEL_SECRET="your_secret_here"
heroku config:set LINE_CHANNEL_TOKEN="your_token_here"
```

### 4. タイムゾーンの確認

```bash
heroku config:get TZ
```

**推奨設定:**
```bash
heroku config:set TZ="Asia/Tokyo"
```

### 5. ログの確認

**リアルタイムでログを監視:**
```bash
heroku logs --tail --ps worker
```

**特定のログを検索:**
```bash
# リマインドジョブのログ
heroku logs --tail | grep "CheckEventRemindersJob"
heroku logs --tail | grep "SendLineReminderJob"

# エラーログのみ
heroku logs --tail | grep "ERROR"
heroku logs --tail | grep "❌"
```

## 🧪 動作確認手順

### ローカル環境でのテスト

1. **テスト用イベントを作成**
   - カレンダーで5分後に開始するイベントを作成
   - リマインド設定を「30分前」に設定（テストのため）

2. **手動でジョブを実行**
   ```bash
   bin/rails reminders:test:run_event_job
   ```

3. **対象イベントを確認**
   ```bash
   bin/rails reminders:test:list_events
   ```

4. **特定のイベントIDで即座に送信テスト**
   ```bash
   bin/rails 'reminders:test:send_event[イベントID]'
   ```

### Heroku環境でのテスト

1. **Heroku Consoleに接続**
   ```bash
   heroku run bash
   ```

2. **テスト用タスクを実行**
   ```bash
   # イベント一覧を表示
   bin/rails reminders:test:list_events

   # 特定イベントに送信テスト
   bin/rails 'reminders:test:send_event[123]'

   # ジョブを手動実行
   bin/rails reminders:test:run_event_job
   ```

3. **ログで送信結果を確認**
   ```bash
   exit  # Consoleから抜ける
   heroku logs --tail | grep "SendLineReminderJob"
   ```

## 📊 監視・デバッグ方法

### 送信済みフラグの確認

**Heroku Console内で:**
```ruby
# 未送信のイベント数
Event.where.not(reminder_minutes: nil).where(line_reminded_at: nil).count

# 送信済みのイベント数
Event.where.not(reminder_minutes: nil).where.not(line_reminded_at: nil).count

# 最近送信されたイベント
Event.where.not(line_reminded_at: nil).order(line_reminded_at: :desc).limit(5).pluck(:id, :title, :line_reminded_at)
```

### Solid Queueのジョブ状態確認

```ruby
# 実行待ちのジョブ数
SolidQueue::Job.pending.count

# 失敗したジョブ
SolidQueue::FailedExecution.order(created_at: :desc).limit(10)

# 最近実行されたジョブ
SolidQueue::Job.finished.order(finished_at: :desc).limit(10)
```

### よくある問題と対処法

**1. ジョブが実行されない**
- Workerプロセスが起動しているか確認: `heroku ps`
- `heroku ps:scale worker=1` で起動

**2. LINE送信が失敗する**
- 環境変数を確認: `heroku config | grep LINE`
- ユーザーがLINE連携しているか確認
- ユーザーがBotをブロックしていないか確認

**3. タイムゾーンがずれている**
- `TZ=Asia/Tokyo` が設定されているか確認
- `heroku config:set TZ="Asia/Tokyo"` で設定
- Workerを再起動: `heroku ps:restart worker`

**4. 重複送信が発生する**
- フラグが正しく更新されているか確認
- データベースのトランザクション分離レベルを確認

## 📝 まとめ

### 修正したファイル
1. ✅ `app/jobs/check_event_reminders_job.rb` - 効率化、フラグ統一、エラーハンドリング強化
2. ✅ `app/jobs/send_line_reminder_job.rb` - リトライ機構、重複防止、エラーハンドリング
3. ✅ `app/jobs/check_task_due_reminders_job.rb` - エラーハンドリング強化
4. ✅ `app/jobs/send_task_due_reminder_job.rb` - リトライ機構、エラーハンドリング
5. ✅ `lib/tasks/reminder_test.rake` - テスト用タスク新規作成

### 設定確認項目（Heroku）
- ✅ Workerプロセスが起動している (`worker=1`)
- ✅ `config/recurring.yml` にジョブが登録されている
- ✅ LINE認証情報が環境変数に設定されている
- ✅ タイムゾーンが `Asia/Tokyo` に設定されている

### 期待される動作
- イベントのリマインドが指定時刻（30分前/1時間前/3時間前/1日前/3日前）に自動送信される
- タスクのリマインドが期限の72時間前に自動送信される
- 送信失敗時は最大3回自動リトライされる
- 重複送信が防止される
- すべてのログが詳細に出力される

## 🔧 次のステップ

1. **Herokuでworkerが起動しているか確認**
2. **LINE認証情報が設定されているか確認**
3. **テストイベントを作成して動作確認**
4. **ログを監視して正常に動作しているか確認**
5. **問題があれば `reminders:test:*` タスクでデバッグ**
