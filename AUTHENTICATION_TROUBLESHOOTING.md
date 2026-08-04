# 支援報告書一覧 認証問題トラブルシューティング

## 📋 問題の概要

「支援報告書一覧」リンクをクリックすると、認証フィルターによってログインページ（`/users/sign_in`）にリダイレクトされる問題。

---

## 🔍 原因の診断

### 認証フローの構造

```
ブラウザ → support_reports_path
          ↓
ApplicationController (authenticate_user!)
          ↓
SupportReportsController
          ├─ before_action :set_character
          └─ before_action :set_organization
          ↓
set_character メソッド
          ├─ current_user が nil? → ログインページへリダイレクト
          └─ character が nil? → root_path へリダイレクト
```

### リダイレクトが発生する3つの原因

#### 1. **ユーザーがログインしていない（最も一般的）**
- セッションが存在しない
- Cookie が無効化されている
- ログアウト済み

**症状:**
```
⚠️ set_character: current_user is nil - User not logged in
⚠️ Redirecting to: /users/sign_in
```

**解決策:**
```
http://localhost:3000/users/sign_in にアクセス
メールアドレス: demo@example.com
パスワード: password123
```

#### 2. **セッションが切れている**
- タイムアウト（デフォルト: 3時間）
- Cookie の SameSite 設定の問題
- PWA/Turbo のキャッシュ問題

**症状:**
- 一度ログインしても、再度アクセスするとログインページに戻される
- ブラウザのコンソールに CSRF エラー

**解決策:**
```bash
# ブラウザの開発者ツールで Cookie を確認
# _task_character_session が存在するか確認
```

#### 3. **ユーザーにキャラクターが紐付いていない**
- データベースの不整合
- アカウント作成時のエラー

**症状:**
```
❌ set_character: Character not found for user 1 (demo@example.com)
```

**解決策:**
```bash
rails runner "
user = User.find_by(email: 'demo@example.com')
if user && !user.character
  user.create_default_character
  puts '✅ キャラクターを作成しました'
end
"
```

---

## 🔧 実装した修正内容

### 1. **デバッグログの追加**

**ファイル:** `app/controllers/support_reports_controller.rb`

```ruby
before_action :log_auth_debug, if: -> { Rails.env.development? }

def log_auth_debug
  Rails.logger.info "🔍 SupportReportsController - Authentication Debug:"
  Rails.logger.info "  - Action: #{action_name}"
  Rails.logger.info "  - User logged in: #{user_signed_in?}"
  Rails.logger.info "  - Current user ID: #{current_user&.id}"
  Rails.logger.info "  - Current user email: #{current_user&.email}"
  Rails.logger.info "  - Character exists: #{current_user&.character.present?}"
  Rails.logger.info "  - Character ID: #{current_user&.character&.id}"
  Rails.logger.info "  - Organization ID: #{current_user&.organization_id}"
end
```

**効果:**
- 開発環境でアクセス時に詳細なログが出力される
- 問題の原因を特定しやすくなる

---

### 2. **エラーメッセージの改善**

**ファイル:** `app/controllers/application_controller.rb`

**Before:**
```ruby
def set_character
  unless current_user
    redirect_to root_path, alert: "ログインが必要です。"
    return
  end
  # ...
end
```

**After:**
```ruby
def set_character
  unless current_user
    Rails.logger.warn "⚠️ set_character: current_user is nil - User not logged in"
    Rails.logger.warn "⚠️ Redirecting to: #{new_user_session_path}"
    flash[:alert] = "この機能を利用するにはログインが必要です。"
    redirect_to new_user_session_path  # 直接ログインページへ
    return
  end

  @character = current_user.character
  unless @character
    Rails.logger.error "❌ set_character: Character not found for user #{current_user.id} (#{current_user.email})"
    flash[:alert] = "キャラクターが見つかりません。アカウント設定を確認してください。"
    redirect_to root_path
    nil
  end
end
```

**効果:**
- ログで問題の原因を追跡可能
- より明確なエラーメッセージをユーザーに表示
- ログイン不要の場合は直接ログインページへリダイレクト

---

### 3. **ログインページの改善**

**ファイル:** `app/views/devise/sessions/new.html.haml`

```haml
/ アラートメッセージ
- if alert.present?
  .bg-yellow-50.border.border-yellow-200.rounded.p-4.mb-4
    %p.text-sm.text-yellow-800
      ⚠️
      = alert

/ デバッグ情報（開発環境のみ）
- if Rails.env.development?
  .bg-slate-100.border.border-slate-300.rounded.p-4.mb-4
    %p.text-xs.text-slate-700.font-mono
      🔧 開発環境デバッグ情報
    %p.text-xs.text-slate-600.font-mono.mt-1
      テストアカウント: demo@example.com / password123
```

**効果:**
- リダイレクト理由が alert に表示される
- 開発環境ではテストアカウント情報が表示される

---

## 🚀 トラブルシューティング手順

### ステップ1: ログイン状態の確認

```bash
# ブラウザの開発者ツール（F12）を開く
# Application タブ → Cookies → http://localhost:3000
# _task_character_session が存在するか確認
```

### ステップ2: ログインを試行

```
1. http://localhost:3000/users/sign_in にアクセス
2. メールアドレス: demo@example.com
3. パスワード: password123
4. 「ログイン」ボタンをクリック
```

### ステップ3: ログが出力されているか確認

```bash
# ターミナルでRailsログを監視
tail -f log/development.log | grep "SupportReportsController"
```

**期待される出力:**
```
🔍 SupportReportsController - Authentication Debug:
  - Action: index
  - User logged in: true
  - Current user ID: 1
  - Current user email: demo@example.com
  - Character exists: true
  - Character ID: 1
  - Organization ID: 1
```

### ステップ4: キャラクターの存在確認

```bash
rails runner "
user = User.find_by(email: 'demo@example.com')
puts '=== キャラクター確認 ==='
puts \"User ID: #{user&.id}\"
puts \"Character exists: #{user&.character.present?}\"
puts \"Character ID: #{user&.character&.id}\"
puts \"Character Name: #{user&.character&.name}\"
"
```

### ステップ5: セッション設定の確認

```bash
# config/initializers/session_store.rb を確認
# または
rails runner "puts Rails.application.config.session_options.inspect"
```

---

## 🔒 セキュリティに関する注意

### 認証を無効化する方法（非推奨）

**もし支援報告書一覧をログイン不要にする場合（セキュリティリスク大）:**

```ruby
# app/controllers/support_reports_controller.rb
class SupportReportsController < ApplicationController
  # 認証をスキップ（セキュリティリスク大）
  skip_before_action :authenticate_user!, only: [:index]
  skip_before_action :set_character, only: [:index]
  skip_before_action :set_organization, only: [:index]
  
  def index
    # 認証なしでアクセス可能
    # ただし、個人情報が漏洩するリスクがある
  end
end
```

**⚠️ 警告:**
- 支援報告書には個人情報が含まれる
- ログイン不要にするとセキュリティリスクが発生
- 本番環境では絶対に推奨しない

---

## 📊 現在の認証設定

### ApplicationController

```ruby
# すべてのコントローラーで認証必須
before_action :authenticate_user!
```

### SupportReportsController

```ruby
# キャラクターと組織の設定が必須
before_action :set_character
before_action :set_organization
```

### 認証除外されているコントローラー

```ruby
# DashboardsController
skip_before_action :authenticate_user!, only: [:show]

# LineLoginController
before_action :authenticate_user!, except: [:callback]
```

---

## 💡 推奨される解決策

### 1. **ログインを維持する（推奨）**

```haml
/ app/views/devise/sessions/new.html.haml
= f.check_box :remember_me
= f.label :remember_me, "ログイン状態を保持"
```

### 2. **セッションタイムアウトを延長**

```ruby
# config/initializers/devise.rb
config.timeout_in = 24.hours  # デフォルト: 3時間
```

### 3. **PWA対応の改善**

```javascript
// Service Worker でセッションCookieを適切に処理
```

---

## 🧪 テスト方法

### 1. ログイン後の動作確認

```bash
# 1. ログイン
curl -c cookies.txt -X POST http://localhost:3000/users/sign_in \
  -d "user[email]=demo@example.com" \
  -d "user[password]=password123"

# 2. 支援報告書一覧にアクセス
curl -b cookies.txt http://localhost:3000/support_reports
```

### 2. ブラウザでの確認

```
1. シークレットモード/プライベートブラウジングで開く
2. http://localhost:3000/support_reports に直接アクセス
3. ログインページにリダイレクトされることを確認
4. ログイン後、support_reports_path にリダイレクトされることを確認
```

---

## 📝 チェックリスト

デバッグ時の確認事項:

- [ ] ユーザーがログインしているか確認
- [ ] ブラウザの Cookie が有効か確認
- [ ] セッションCookie（_task_character_session）が存在するか確認
- [ ] ログに "current_user is nil" が出力されているか確認
- [ ] キャラクターが存在するか確認（rails runner で確認）
- [ ] CSRF トークンエラーが出ていないか確認
- [ ] ブラウザのコンソールにエラーが出ていないか確認

---

## 🆘 さらなるサポート

問題が解決しない場合:

1. **ログを確認:**
   ```bash
   tail -f log/development.log
   ```

2. **セッションをクリア:**
   ```bash
   rm -rf tmp/cache tmp/sessions
   touch tmp/restart.txt
   ```

3. **ブラウザのキャッシュをクリア:**
   - Chrome: Ctrl+Shift+Del
   - Cookie とキャッシュをすべて削除

4. **データベースの確認:**
   ```bash
   rails console
   User.count
   Character.count
   user = User.first
   user.character
   ```

---

**作成日:** 2026-08-04  
**対象環境:** Rails 8.0.4 / Ruby 3.4.1 / Devise認証
