# タスクLINE送信時のカテゴリ表示修正

## 🔍 問題の特定

### 原因
`Task#category_display`メソッドが、カレンダーの`Event#display_category_name`と異なるロジックを使用していた：

1. **古いハードコードされたカテゴリ**
   - "welfare"（訪問福祉）、"web"（Web制作）、"admin"（事務作業）など
   - これらは現在のシステムで使用されていない

2. **カスタムカテゴリの処理が不完全**
   - 配列/ハッシュ変換の処理が複雑
   - `custom_`プレフィックスのチェックが欠落

3. **カレンダーとの不一致**
   - Event: `display_category_name` メソッド
   - Task: `category_display` メソッド
   - 異なるロジックで実装されていた

## ✅ 実施した修正

### 1. Task#category_display メソッドの統一 ([app/models/task.rb](app/models/task.rb))

**修正前:**
```ruby
def category_display
  case category
  when "welfare"
    "訪問福祉 🏠"
  when "web"
    "Web制作 💻"
  when "admin"
    "事務作業 📋"
  when "personal"
    "個人"
  # ...
  else
    # 複雑なカスタムカテゴリ処理
  end
end
```

**修正後:**
```ruby
def category_display
  settings = character&.calendar_settings_hash || {}

  # カスタムカテゴリの名前を取得（category が custom_ で始まる場合）
  if category.to_s.start_with?("custom_") && settings["custom_categories"].present?
    custom_categories = settings["custom_categories"]
    
    # インデックス付きハッシュを配列に変換（ActionController::Parameters対応）
    if custom_categories.is_a?(Hash) && custom_categories.keys.all? { |k| k.to_s =~ /^\d+$/ }
      custom_categories = custom_categories.values
    end
    
    if custom_categories.is_a?(Array)
      cat = custom_categories.find { |c| c["id"] == category.to_s }
      return cat["name"] if cat&.dig("name")
    end
  end

  # 固定カテゴリの名前
  case category
  when "personal"
    "個人"
  when "work"
    "仕事"
  when "meeting"
    "ミーティング"
  when "task_deadline"
    "タスク期限"
  else
    category || "未設定"
  end
end
```

### 主な改善点

1. **Event#display_category_name と同じロジック**
   - `custom_`プレフィックスのチェック
   - カスタムカテゴリの正確な検索
   - フォールバック処理の統一

2. **固定カテゴリの統一**
   - 古いカテゴリ（welfare, web, admin）を削除
   - 現在使用されているカテゴリのみに限定
   - カレンダーと同じ名称を使用

3. **エラーハンドリング**
   - `character&.calendar_settings_hash || {}` で安全な取得
   - `cat&.dig("name")` で安全なアクセス
   - フォールバック値として `category || "未設定"`

## 📝 影響範囲

この修正により、以下の箇所でカテゴリ表示が統一されます：

### 1. TasksController#notify_line ([app/controllers/tasks_controller.rb](app/controllers/tasks_controller.rb))

**LINE送信時:**
```ruby
category_name = @task.category_display || "未設定"

message = <<~TEXT.strip
  🔔 タスクが登録されました！

  【カテゴリ】 #{category_name}
  【タスク名】 #{@task.title}
  【期限】 #{due_text}
TEXT
```

### 2. LineBotService#send_task_due_reminder ([app/services/line_bot_service.rb](app/services/line_bot_service.rb))

**72時間前リマインド:**
```ruby
category_name = task.category_display || "未設定"

text = <<~TEXT.strip
  🔔 タスクの期限が近づいています（72時間前）

  【カテゴリ】 #{category_name}
  【タスク名】 #{task.title}
  【期限】 #{due_str}
TEXT
```

### 3. ビュー全体
- [app/views/tasks/_task_card.html.haml](app/views/tasks/_task_card.html.haml)
- [app/views/tasks/_task_item.html.haml](app/views/tasks/_task_item.html.haml)
- [app/views/tasks/hidden.html.haml](app/views/tasks/hidden.html.haml)
- その他すべてのタスク表示箇所

## 🧪 動作確認手順

### 1. カスタムカテゴリを設定
```
1. カレンダー画面右上の「⚙️ 設定」をクリック
2. カスタムカテゴリを追加（例: 「プロジェクトA」）
3. 保存
```

### 2. タスクを作成
```
1. タスク画面で新規タスクを作成
2. カテゴリに「プロジェクトA」（または任意のカスタムカテゴリ）を選択
3. タイトル、期限などを入力して保存
```

### 3. LINE送信テスト
```
1. 作成したタスクの「LINEへ通知」ボタンをクリック
2. LINEアプリを確認
3. 【カテゴリ】が「プロジェクトA」と正しく表示されることを確認
```

### 4. 固定カテゴリの確認
```
1. 「個人」「仕事」「ミーティング」などの固定カテゴリでタスク作成
2. LINE送信
3. カレンダーと同じカテゴリ名が表示されることを確認
```

## 📊 テスト用Railsコンソールコマンド

```ruby
# 1. タスクのカテゴリ表示を確認
task = Task.last
puts "Category: #{task.category}"
puts "Display: #{task.category_display}"

# 2. カスタムカテゴリの設定を確認
character = Character.first
settings = character.calendar_settings_hash
puts settings["custom_categories"].inspect

# 3. カスタムカテゴリ付きタスクを作成してテスト
task = Task.create!(
  character: character,
  title: "テストタスク",
  category: "custom_12345",  # カスタムカテゴリのID
  dislike_level: 5
)
puts task.category_display  # カスタムカテゴリ名が表示されるはず

# 4. 固定カテゴリのテスト
task = Task.create!(
  character: character,
  title: "個人タスク",
  category: "personal",
  dislike_level: 5
)
puts task.category_display  # "個人" と表示されるはず
```

## 🔍 トラブルシューティング

### ケース1: カスタムカテゴリが「未設定」と表示される

**原因:**
- カスタムカテゴリのIDが間違っている
- `character.calendar_settings_hash` が空

**確認:**
```ruby
task = Task.find(タスクID)
puts task.category  # => "custom_12345" のような形式か確認
puts task.character.calendar_settings_hash["custom_categories"].inspect
```

### ケース2: 固定カテゴリが表示されない

**原因:**
- カテゴリIDが正しくない（タイポなど）

**確認:**
```ruby
task = Task.find(タスクID)
puts task.category  # => "personal", "work", "meeting", "task_deadline" のいずれか
```

### ケース3: カレンダーとタスクでカテゴリ名が異なる

**修正後は統一されています。**
それでも異なる場合：
```ruby
# イベントとタスクのカテゴリ表示を比較
event = Event.last
task = Task.last

puts "Event: #{event.event_type} => #{event.display_category_name}"
puts "Task: #{task.category} => #{task.category_display}"

# 設定を確認
character = Character.first
puts character.calendar_settings_hash["custom_categories"].inspect
```

## ✅ 期待される結果

- ✅ タスクのLINE送信時、カレンダーと同じカテゴリ名が表示される
- ✅ カスタムカテゴリが正しく反映される
- ✅ 固定カテゴリ（個人、仕事、ミーティング）が統一される
- ✅ カテゴリ未設定時は「未設定」と表示される
- ✅ 古いカテゴリ（welfare, web, admin）は削除され、混乱を防ぐ

## 📋 修正ファイル一覧

1. ✅ [app/models/task.rb](app/models/task.rb) - `category_display`メソッドを統一
2. ℹ️ [app/controllers/tasks_controller.rb](app/controllers/tasks_controller.rb) - 変更なし（既に`category_display`使用）
3. ℹ️ [app/services/line_bot_service.rb](app/services/line_bot_service.rb) - 変更なし（既に`category_display`使用）

## 🚀 デプロイ後の確認

Heroku環境で以下を確認：

```bash
# 1. Railsコンソールを起動
heroku run rails console

# 2. カスタムカテゴリの設定を確認
character = Character.first
puts character.calendar_settings_hash["custom_categories"].inspect

# 3. タスクのカテゴリ表示をテスト
task = Task.where.not(category: nil).first
puts "Category: #{task.category}"
puts "Display: #{task.category_display}"

# 4. LINE送信テスト（実際に送信されます）
user = User.where.not(line_user_id: nil).first
character = user.characters.first
task = character.tasks.first

service = LineBotService.new
result = service.send_message(
  user.line_user_id,
  "【テスト】カテゴリ: #{task.category_display}"
)

puts result ? "✅ 送信成功" : "❌ 送信失敗"
```

## 📝 まとめ

タスクのLINE送信時に、カレンダーと完全に統一されたカテゴリ表示が実現されました。カスタムカテゴリ、固定カテゴリともに正しく反映され、ユーザー体験の一貫性が向上します。
