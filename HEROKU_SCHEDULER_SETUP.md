# LINEリマインド自動送信機能 実装ガイド

## 📋 目次

1. [機能概要](#機能概要)
2. [実装内容](#実装内容)
3. [動作の仕組み](#動作の仕組み)
4. [ローカルでの動作確認](#ローカルでの動作確認)
5. [Heroku Schedulerでの自動実行設定](#heroku-schedulerでの自動実行設定)
6. [トラブルシューティング](#トラブルシューティング)

---

## 📌 機能概要

カレンダーイベントとタスクに設定されたリマインド時刻になると、自動的にLINEへ通知を送信する機能です。

### 対象

#### 1. **カレンダーイベントのリマインド**
- イベントに設定された`reminder_minutes`（30分前、1時間前、3時間前、1日前、3日前）に基づいて通知
- 例：会議の1時間前に「会議の時間が近づいています」とLINE通知

#### 2. **タスクの期限リマインド（72時間前）**
- タスクの`due_date`が72時間以内に迫ったタスクについて通知
- 例：締切の3日前に「タスクの期限が近づいています」とLINE通知

---

## 🛠️ 実装内容

### 1. マイグレーション

#### `db/migrate/20260715023408_add_line_reminded_at_to_events.rb`
```ruby
class AddLineRemindedAtToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :line_reminded_at, :datetime
    add_index :events, :line_reminded_at
  end
end
```

**目的:** イベントのLINEリマインド送信済みフラグを記録するカラムを追加

**実行コマンド:**
```bash
bin/rails db:migrate
```

### 2. Rakeタスク

#### `lib/tasks/line_reminders.rake`

3つのタスクを実装：

| コマンド | 説明 |
|---------|------|
| `bin/rails reminders:send_event_reminders` | カレンダーイベントのリマインド送信 |
| `bin/rails reminders:send_task_reminders` | タスクの72時間前リマインド送信 |
| `bin/rails reminders:send_all` | 両方のリマインドを一括送信 |

### 3. モデル更新

#### `app/models/event.rb`
```ruby
# reminder_minutes が変更されたらリマインド送信済みフラグをリセット
before_save :reset_reminder_sent_flag, if: :reminder_minutes_changed?

def reset_reminder_sent_flag
  self.line_reminded_at = nil
end
```

**機能:** リマインド設定を変更したら、再度通知が送られるようにフラグをリセット

### 4. 既存のテーブル

#### `tasks` テーブル
- `line_due_72h_notified_at` カラムは**既に実装済み**
- タスクの72時間前リマインド送信済みフラグを記録

---

## ⚙️ 動作の仕組み

### イベントリマインドの流れ

```
┌─────────────────────────────────────────────────────────┐
│ 1. Heroku Scheduler が10分ごとに実行                     │
│    $ bin/rails reminders:send_all                       │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│ 2. データベースから対象イベントを検索                    │
│    条件:                                                 │
│    - reminder_minutes が設定されている                   │
│    - line_reminded_at が nil（未送信）                   │
│    - リマインド時刻を過ぎている                          │
│    - イベント開始時刻がまだ未来                          │
│    - キャンセルされていない                              │
│    - ユーザーがLINE連携済み                              │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│ 3. リマインド時刻を計算                                  │
│    reminder_time = start_time - reminder_minutes.minutes │
│                                                          │
│    例：14:00開始、1時間前リマインド                      │
│    → 13:00に送信                                         │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│ 4. LineBotService.send_event_reminder で送信             │
│    メッセージ例:                                         │
│    ⏰ リマインド（1時間前）                              │
│                                                          │
│    【カテゴリ】 会議                                     │
│    【件名】 週次ミーティング                             │
│    【開始時刻】 12月15日 14:00                           │
│                                                          │
│    準備はよろしいですか？                                │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│ 5. 送信成功したら line_reminded_at を更新                │
│    重複送信を防止                                        │
└─────────────────────────────────────────────────────────┘
```

### タスクリマインドの流れ

```
┌─────────────────────────────────────────────────────────┐
│ 1. データベースから対象タスクを検索                      │
│    条件:                                                 │
│    - due_date が設定されている                           │
│    - line_due_72h_notified_at が nil（未送信）          │
│    - due_date が現在から72時間以内                       │
│    - 完了していない（completed_at が nil）               │
│    - 非表示ではない                                      │
│    - ユーザーがLINE連携済み                              │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│ 2. LineBotService.send_task_due_reminder で送信          │
│    メッセージ例:                                         │
│    🔔 タスクの期限が近づいています（72時間前）           │
│                                                          │
│    【カテゴリ】 仕事                                     │
│    【タスク名】 プレゼン資料作成                         │
│    【期限】 12月18日 10:00                               │
│                                                          │
│    準備を進めておきましょう！                            │
└────────────────────┬────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│ 3. 送信成功したら line_due_72h_notified_at を更新        │
│    重複送信を防止                                        │
└─────────────────────────────────────────────────────────┘
```

---

## 🧪 ローカルでの動作確認

### 1. マイグレーション実行
```bash
bin/rails db:migrate
```

### 2. Rakeタスクの手動実行

#### すべてのリマインド送信（推奨）
```bash
bin/rails reminders:send_all
```

**出力例:**
```
🚀 すべてのリマインド送信タスクを開始します

================================================================================
[2026-07-15 11:37:13 +0900] イベントリマインド送信タスク開始
================================================================================
📊 リマインド設定されているイベント数: 3
✅ 送信成功: イベント「週次ミーティング」(ID: 123) → U1234567890abcdef
⏰ 待機中: イベント「プレゼン」- あと45分後に送信予定
✅ 送信成功: イベント「ランチ」(ID: 125) → U1234567890abcdef

================================================================================
📊 実行結果サマリー
================================================================================
✅ 送信成功: 2件
❌ 送信失敗: 0件
⏭️ スキップ: 1件
🏁 タスク完了: 2026-07-15 11:37:15 +0900
================================================================================

================================================================================
[2026-07-15 11:37:15 +0900] タスクリマインド送信タスク開始
================================================================================
📊 リマインド対象のタスク数: 1
✅ 送信成功: タスク「レポート提出」(ID: 456) - 期限まで48.5時間 → U1234567890abcdef

================================================================================
📊 実行結果サマリー
================================================================================
✅ 送信成功: 1件
❌ 送信失敗: 0件
⏭️ スキップ: 0件
🏁 タスク完了: 2026-07-15 11:37:15 +0900
================================================================================

🎉 すべてのリマインド送信タスクが完了しました
```

#### イベントリマインドのみ
```bash
bin/rails reminders:send_event_reminders
```

#### タスクリマインドのみ
```bash
bin/rails reminders:send_task_reminders
```

### 3. テストデータの作成

リマインドをテストするには、以下の条件を満たすデータを作成してください：

#### イベント
- `reminder_minutes` を設定（例：30分前）
- `start_time` を未来の時刻に設定
- `line_reminded_at` を nil に設定

#### タスク
- `due_date` を現在から72時間以内に設定
- `line_due_72h_notified_at` を nil に設定
- `completed_at` を nil に設定（未完了）

---

## 🚀 Heroku Schedulerでの自動実行設定

### 前提条件

- Herokuアプリが作成済み
- LINE認証情報が設定済み（`LINE_CHANNEL_SECRET`, `LINE_CHANNEL_TOKEN`）
- PostgreSQLデータベースが接続済み

### ステップ1: Heroku Schedulerアドオンの追加

#### 方法1: Heroku CLIを使用
```bash
# Herokuにログイン
heroku login

# Schedulerアドオンを追加（無料プランの場合）
heroku addons:create scheduler:standard --app your-app-name
```

#### 方法2: Heroku Dashboardから追加
1. [Heroku Dashboard](https://dashboard.heroku.com/) にログイン
2. 該当アプリを選択
3. 「Resources」タブをクリック
4. 「Add-ons」で「Heroku Scheduler」を検索
5. 「Heroku Scheduler」を選択して「Submit Order Form」をクリック

### ステップ2: Schedulerの設定

#### 方法1: Heroku CLIから設定
```bash
# Schedulerを開く
heroku addons:open scheduler --app your-app-name
```

#### 方法2: Heroku Dashboardから設定
1. 「Resources」タブで「Heroku Scheduler」をクリック
2. 「Create job」ボタンをクリック

### ステップ3: ジョブの作成

#### 設定内容

| 項目 | 設定値 |
|-----|-------|
| **Schedule** | Every 10 minutes（10分ごと） |
| **Run Command** | `bin/rails reminders:send_all` |

**推奨設定:**
- **10分ごと実行** → リアルタイムに近いリマインド送信
- または **1時間ごと実行** → サーバー負荷を抑えたい場合

#### 詳細設定手順

1. **「Create job」をクリック**

2. **Schedule（実行頻度）を選択:**
   - `Every 10 minutes` （推奨：リアルタイム性重視）
   - `Every hour` （サーバー負荷を抑えたい場合）
   - `Every day at...` （1日1回のリマインドで十分な場合）

3. **Run Command（実行コマンド）を入力:**
   ```bash
   bin/rails reminders:send_all
   ```

4. **Dyno Size（インスタンスサイズ）を選択:**
   - `Basic` または `Standard-1X` （推奨）

5. **「Save Job」をクリック**

### ステップ4: 動作確認

#### ログの確認
```bash
# リアルタイムログを確認
heroku logs --tail --app your-app-name

# 最近のログを確認
heroku logs --num 500 --app your-app-name | grep reminders
```

#### 実行履歴の確認
1. Heroku Dashboard → 該当アプリ → Resources → Heroku Scheduler
2. ジョブの実行履歴が表示される
3. 「Last run」で最終実行時刻を確認
4. 「Next run」で次回実行予定時刻を確認

### ステップ5: マイグレーションの実行（初回のみ）

```bash
# Herokuでマイグレーションを実行
heroku run bin/rails db:migrate --app your-app-name
```

---

## 🔍 トラブルシューティング

### 1. リマインドが送信されない

#### 原因1: LINE認証情報が設定されていない
**確認方法:**
```bash
heroku config --app your-app-name | grep LINE
```

**解決方法:**
```bash
heroku config:set LINE_CHANNEL_SECRET=your_secret --app your-app-name
heroku config:set LINE_CHANNEL_TOKEN=your_token --app your-app-name
```

#### 原因2: ユーザーがLINE連携していない
**確認方法:**
- データベースで `users.line_user_id` が設定されているか確認

**解決方法:**
- ユーザーにLINE連携を依頼

#### 原因3: リマインド設定がされていない
**確認方法:**
- イベントの `reminder_minutes` が nil ではないか確認
- タスクの `due_date` が設定されているか確認

**解決方法:**
- カレンダーでイベント作成時にリマインドを設定
- タスク作成時に期限日時を設定

#### 原因4: 既に送信済み
**確認方法:**
```bash
# Heroku Railsコンソール起動
heroku run bin/rails console --app your-app-name

# イベントのリマインド送信状況を確認
Event.where.not(reminder_minutes: nil).where.not(line_reminded_at: nil).count

# タスクのリマインド送信状況を確認
Task.where.not(due_date: nil).where.not(line_due_72h_notified_at: nil).count
```

**解決方法（テスト目的でリセットする場合）:**
```ruby
# 特定のイベントのリマインドフラグをリセット
event = Event.find(123)
event.update_column(:line_reminded_at, nil)

# 特定のタスクのリマインドフラグをリセット
task = Task.find(456)
task.update_column(:line_due_72h_notified_at, nil)
```

### 2. Heroku Schedulerが実行されない

#### 確認方法
```bash
# Schedulerアドオンが有効か確認
heroku addons --app your-app-name | grep scheduler
```

#### 解決方法
- Heroku Dashboardで「Resources」→「Heroku Scheduler」が追加されているか確認
- ジョブが「Active」状態になっているか確認

### 3. エラーログの確認

#### エラーが発生している場合
```bash
# エラーログを検索
heroku logs --tail --app your-app-name | grep ERROR

# Rakeタスクのログを検索
heroku logs --tail --app your-app-name | grep reminders
```

#### よくあるエラー

**エラー1: `Gem::LoadError: cannot load such file -- line-bot-api-v2`**
**解決方法:**
```bash
# Gemfileにline-bot-api-v2が含まれているか確認
heroku run bundle list --app your-app-name | grep line-bot-api

# 含まれていない場合はGemfileに追加してデプロイ
```

**エラー2: `PG::ConnectionBad: connection to server failed`**
**解決方法:**
```bash
# データベースが接続されているか確認
heroku pg:info --app your-app-name

# データベースを再起動
heroku pg:restart --app your-app-name
```

### 4. 送信頻度の調整

#### 10分ごとでは頻繁すぎる場合
- Heroku Schedulerの設定を「Every hour」に変更

#### 1時間ごとでは遅すぎる場合
- 「Every 10 minutes」に変更
- または無料枠を超える場合は有料プランを検討

---

## 📊 モニタリング

### ログで送信状況を監視

```bash
# リマインド送信の成功・失敗を確認
heroku logs --tail --app your-app-name | grep "送信成功\|送信失敗"

# 実行結果サマリーを確認
heroku logs --tail --app your-app-name | grep "実行結果サマリー" -A 5
```

### データベースで送信履歴を確認

```bash
# Railsコンソールを起動
heroku run bin/rails console --app your-app-name

# 最近送信されたイベントリマインド
Event.where.not(line_reminded_at: nil).order(line_reminded_at: :desc).limit(10)

# 最近送信されたタスクリマインド
Task.where.not(line_due_72h_notified_at: nil).order(line_due_72h_notified_at: :desc).limit(10)
```

---

## 🎉 完了

これでLINEリマインド自動送信機能が本番環境（Heroku）で動作するようになりました！

### チェックリスト

- [ ] マイグレーション実行完了（`line_reminded_at` カラム追加）
- [ ] Rakeタスク実装完了（`lib/tasks/line_reminders.rake`）
- [ ] ローカルでの動作確認完了
- [ ] Heroku Schedulerアドオン追加完了
- [ ] Heroku Schedulerジョブ作成完了（10分ごとに実行）
- [ ] Herokuでマイグレーション実行完了
- [ ] LINE認証情報設定完了
- [ ] Herokuログで動作確認完了

### サポート

問題が発生した場合は、以下の情報を提供してください：
1. Herokuログ（`heroku logs --tail`）
2. エラーメッセージ
3. データベースの状態（該当イベント/タスクの情報）

---

**作成日:** 2026-07-15  
**バージョン:** 1.0
