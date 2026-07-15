# LINEリマインド自動送信 - デバッグガイド

## 🐛 リマインドが届かない場合のデバッグ手順

### 1️⃣ まず最初にこれを実行

```bash
# ローカル環境
bin/rails reminders:check_status

# Heroku環境
heroku run bin/rails reminders:check_status --app your-app-name
```

**このコマンドで全てが分かります:**
- ✅ リマインド設定されているイベント/タスクの数
- ✅ 未送信/送信済みの件数
- ✅ 各イベントの詳細（開始時刻、リマインド時刻、LINE ID）
- ✅ 送信対象かどうかの判定結果

---

## 📊 よくある原因

### ❌ 「リマインド対象候補数: 0件」と表示される

**原因1: 未来のイベントがない**
→ カレンダーに未来のイベントを作成してください

**原因2: リマインド設定がされていない**
→ イベント作成時に「リマインド」を設定してください（30分前、1時間前など）

**原因3: LINE連携がされていない**
→ ユーザーがLINE連携していることを確認してください

**原因4: 既に送信済み**
→ 正常に動作しています（新しいイベントでテストしてください）

---

## 🔧 Rakeタスク一覧

### メインタスク

```bash
# すべてのリマインドを送信（Heroku推奨）
bin/rails reminders:send_all
# または
bin/rails reminders:send_line

# イベントリマインドのみ
bin/rails reminders:send_event_reminders

# タスクリマインドのみ
bin/rails reminders:send_task_reminders
```

### デバッグタスク

```bash
# 状態確認（送信なし）
bin/rails reminders:check_status

# 送信済みフラグをリセット（テスト用）
bin/rails reminders:reset_flags
```

---

## 📝 デバッグログの見方

### ✅ 正常に動作している場合

```
📊 リマインド対象候補数: 3件

🔔 処理中: イベント「会議」(ID: 123)
  判定: ✅ リマインド時刻を過ぎています → 送信対象
  LINE送信先: U1234567890abcdef
  送信開始...
  結果: ✅ 送信成功！

📊 実行結果サマリー
✅ 送信成功: 3件
```

### ⏰ リマインド時刻前の場合

```
🔔 処理中: イベント「会議」(ID: 123)
  判定: ⏰ まだリマインド時刻に達していません
  結果: ⏭️ スキップ（あと45分後に送信予定）
```

→ これは正常です。指定時刻になれば自動で送信されます。

### 🚫 送信対象がない場合

```
📊 リマインド対象候補数: 0件

📊 実行結果サマリー
✅ 送信成功: 0件
❌ 送信失敗: 0件
⏭️ スキップ: 0件
```

→ 未来のリマインド対象イベントがないだけです（正常）。

---

## 🔍 Herokuでのデバッグ

### ログをリアルタイムで確認

```bash
# すべてのログ
heroku logs --tail --app your-app-name

# リマインド関連のみ
heroku logs --tail --app your-app-name | grep reminders

# 送信成功/失敗のみ
heroku logs --tail --app your-app-name | grep "送信成功\|送信失敗"
```

### LINE認証情報を確認

```bash
heroku config --app your-app-name | grep LINE
```

出力例:
```
LINE_CHANNEL_SECRET: your_secret_here
LINE_CHANNEL_TOKEN:  your_token_here
```

### Heroku Schedulerの実行履歴を確認

```bash
heroku addons:open scheduler --app your-app-name
```

---

## 📖 詳細ガイド

より詳しい情報は以下を参照してください：

- [HEROKU_SCHEDULER_SETUP.md](HEROKU_SCHEDULER_SETUP.md) - Heroku設定とトラブルシューティング
- [LINE_NOTIFICATION_CATEGORY_SYNC.md](LINE_NOTIFICATION_CATEGORY_SYNC.md) - LINE通知機能の仕様

---

**更新日:** 2026-07-15  
**バージョン:** 1.0
