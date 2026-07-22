# 【新機能】秘書エージェントでのタスクLINE送信機能

## 📋 概要

秘書エージェント（AIチャット）で、「今日のタスクをLINEに送って」「期限が近いタスク3つLINEに送って」といった指示を受けた際に、該当するタスクを自動抽出してユーザーのLINEへメッセージとして送信する機能を実装しました。

## ✨ 実装内容

### 1. TaskLineNotifierService の作成

**ファイル:** [app/services/task_line_notifier_service.rb](app/services/task_line_notifier_service.rb)

タスクを条件に基づいて抽出し、LINEメッセージを構築して送信するサービスクラスです。

**主な機能:**
- 時間枠フィルタ（今日、明日、今週、来週、期限切れ）
- フィルタータイプ（期限が近い、未完了）
- 件数制限（1〜50件）
- カテゴリ名の正確な表示（カレンダーと統一）
- 期限の見やすいフォーマット

**LINEメッセージ例:**
```
📅 今日のタスク（3件）
--------------------
1. [仕事] 企画書の作成 (今日 15:00)
2. [個人] メール返信 (今日 18:00)
3. [ミーティング] 定例会議の準備 (今日 16:30)
--------------------
タスク管理アプリで詳細を確認できます 📱
```

### 2. AI秘書にTool Calling機能を追加

**ファイル:** [app/controllers/ai_secretary_controller.rb](app/controllers/ai_secretary_controller.rb)

OpenAI APIのTool Calling（Function Calling）を使用して、AIが自動的にタスクをLINEに送信できるようにしました。

**追加メソッド:**
- `define_tools`: AIが使用できるツール（関数）を定義
- `execute_tools`: ツールを実行し、結果を返す
- `execute_send_tasks_to_line`: タスクLINE送信ツールの実装

**ツール定義:**
```ruby
{
  name: "send_tasks_to_line",
  description: "ユーザーが指定した条件に基づいてタスクを抽出し、LINEに送信します",
  parameters: {
    time_frame: "today" | "tomorrow" | "this_week" | "next_week" | "overdue" | "all",
    limit: 1〜50（デフォルト: 10）,
    filter_type: "nearing_deadline" | "uncompleted" | "all"
  }
}
```

### 3. システムプロンプトの更新

AI秘書のシステムプロンプトに、LINE送信機能の説明を追加しました。

**追加内容:**
```
【LINEへのタスク送信機能】
ユーザーが「今日のタスクをLINEに送って」「期限が近いタスク3つLINEに送って」などと依頼した場合、
send_tasks_to_line関数を使用してタスクをLINEに送信できます。

関数実行後、結果に基づいて「○件のタスクをLINEに送信しました！」と報告してください。
送信失敗時はその旨を伝え、代替案を提示してください。
```

## 🎯 使用例

### 基本的な使い方

AI秘書チャットで以下のような指示を出すと、自動的にタスクをLINEに送信します：

1. **今日のタスクを送信**
   ```
   ユーザー: 今日のタスクをLINEに送って
   AI秘書: 承知しました！今日のタスク3件をLINEに送信しました📱
   ```

2. **期限が近いタスクを送信**
   ```
   ユーザー: 期限が近いタスク5つLINEに送って
   AI秘書: 期限が近いタスク5件をLINEに送信しました！準備はいかがですか？
   ```

3. **明日のタスクを送信**
   ```
   ユーザー: 明日のタスク教えて。LINEにも送っといて
   AI秘書: 明日のタスクは以下の3件です。LINEにも送信しておきました📱
   ```

4. **期限切れタスクを送信**
   ```
   ユーザー: 期限切れのタスクをLINEに送信
   AI秘書: 期限切れのタスク2件をLINEに送信しました。早めの対応をお勧めします⚠️
   ```

### パラメータの指定

- **時間枠:** 今日、明日、今週、来週、期限切れ
- **件数:** 「3つ」「5件」など
- **フィルター:** 「期限が近い」「未完了の」など

## 🔧 技術詳細

### Tool Calling のフロー

1. ユーザーがメッセージを送信
2. AI秘書が意図を解析
3. LINE送信が必要と判断した場合、`send_tasks_to_line`ツールを呼び出し
4. `TaskLineNotifierService`がタスクを抽出
5. LINEメッセージを構築して送信
6. 結果をAI秘書に返す
7. AI秘書がユーザーに結果を報告

### エラーハンドリング

以下の場合、適切なエラーメッセージを返します：

1. **LINE未連携**
   ```json
   {
     "success": false,
     "message": "LINE連携が完了していません。設定画面からLINE連携を行ってください。",
     "tasks_count": 0
   }
   ```

2. **該当タスクなし**
   ```json
   {
     "success": false,
     "message": "指定された条件に一致するタスクが見つかりませんでした。",
     "tasks_count": 0
   }
   ```

3. **送信失敗**
   ```json
   {
     "success": false,
     "message": "LINEへの送信に失敗しました。しばらく経ってから再度お試しください。",
     "tasks_count": 0
   }
   ```

## 🧪 テスト方法

### 1. ローカル環境でのテスト

```bash
# Railsコンソールを起動
bin/rails console
```

```ruby
# 1. サービスクラスを直接テスト
character = Character.first

# 今日のタスクを抽出（送信はしない）
service = TaskLineNotifierService.new(
  character: character,
  filters: { time_frame: "today", limit: 5 }
)

# タスク数を確認
tasks = service.send(:extract_tasks)
puts "対象タスク数: #{tasks.count}"

# LINEメッセージを確認（送信はしない）
message = service.send(:build_line_message, tasks)
puts message

# 2. 実際にLINE送信をテスト（LINE連携済みの場合）
result = service.send_tasks_to_line
puts result.inspect
```

### 2. AI秘書経由でのテスト

1. AI秘書チャット画面を開く
2. テスト用タスクを作成
   - 今日の日時で期限を設定
   - カテゴリを設定
3. AI秘書に指示
   ```
   今日のタスクをLINEに送って
   ```
4. LINEアプリで受信を確認

### 3. 様々なパターンでテスト

```
# パターン1: 時間枠指定
- 今日のタスクをLINEに送って
- 明日のタスクをLINEに送って
- 今週のタスクをLINEに送って
- 期限切れタスクをLINEに送って

# パターン2: 件数指定
- タスク3つLINEに送って
- 期限が近いタスク5件LINEに送って

# パターン3: フィルター指定
- 期限が近いタスクをLINEに送って
- 未完了タスクをLINEに送って

# パターン4: 組み合わせ
- 今日のタスク3つをLINEに送って
- 明日の期限が近いタスク5件をLINEに送って
```

## 📊 動作確認チェックリスト

### 基本機能
- [ ] 今日のタスクが正しく抽出される
- [ ] 指定した件数でタスクが抽出される
- [ ] LINEメッセージが送信される
- [ ] カテゴリ名が正しく表示される
- [ ] 期限が見やすくフォーマットされる

### エラーハンドリング
- [ ] LINE未連携時にエラーメッセージが表示される
- [ ] 該当タスクなし時にメッセージが表示される
- [ ] 送信失敗時にエラーメッセージが表示される

### AI秘書の応答
- [ ] ツール実行後に結果を報告する
- [ ] 送信成功時に件数を報告する
- [ ] エラー時に代替案を提示する

### 各種フィルター
- [ ] today（今日）
- [ ] tomorrow（明日）
- [ ] this_week（今週）
- [ ] next_week（来週）
- [ ] overdue（期限切れ）
- [ ] nearing_deadline（期限が近い）

## 🔍 トラブルシューティング

### 問題1: ツールが呼び出されない

**原因:** AI秘書がユーザーの意図を正しく理解していない

**対処法:**
- 明確な指示を出す（「LINEに送って」を含める）
- システムプロンプトを確認
- OpenAI APIのログを確認

### 問題2: LINEに送信されない

**原因:** LINE連携がされていない、または`line_user_id`が設定されていない

**対処法:**
```ruby
# Railsコンソールで確認
user = User.first
puts user.line_user_id.present?  # => true であるべき
```

### 問題3: カテゴリ名が正しく表示されない

**原因:** `Task#category_display`メソッドの問題

**対処法:**
```ruby
# Railsコンソールで確認
task = Task.last
puts "Category: #{task.category}"
puts "Display: #{task.category_display}"

# カスタムカテゴリの設定を確認
character = task.character
settings = character.calendar_settings_hash
puts settings["custom_categories"].inspect
```

### 問題4: タスクが抽出されない

**原因:** フィルター条件に一致するタスクがない

**対処法:**
```ruby
# Railsコンソールで確認
character = Character.first

# 今日のタスク数を確認
today_start = Time.current.beginning_of_day
today_end = Time.current.end_of_day
tasks = character.tasks.pending.visible.where(due_date: today_start..today_end)
puts "今日のタスク数: #{tasks.count}"
```

## 📝 まとめ

### 実装したファイル
1. ✅ [app/services/task_line_notifier_service.rb](app/services/task_line_notifier_service.rb) - タスク抽出・LINE送信サービス
2. ✅ [app/controllers/ai_secretary_controller.rb](app/controllers/ai_secretary_controller.rb) - Tool Calling機能の追加

### 主な機能
- ✅ AI秘書がユーザーの指示を理解してタスクをLINEに送信
- ✅ 時間枠、件数、フィルター条件の指定
- ✅ カレンダーと統一されたカテゴリ表示
- ✅ 見やすい期限表示
- ✅ エラーハンドリング

### 今後の拡張可能性
- 特定カテゴリのみを送信
- タスクの優先度でフィルター
- 定期的な自動送信（毎朝8時など）
- タスクの進捗状況も含めて送信
- LINE以外の通知先（Slack、メールなど）

## 🚀 デプロイ後の確認

```bash
# Heroku環境で確認
heroku run rails console

# 1. サービスクラスのテスト
character = Character.first
service = TaskLineNotifierService.new(
  character: character,
  filters: { time_frame: "today" }
)
result = service.send_tasks_to_line
puts result.inspect

# 2. AI秘書でテスト
# AI秘書チャット画面で「今日のタスクをLINEに送って」と入力
```
