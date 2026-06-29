# 開発環境でのメール確認機能について

## 概要
開発環境では、実際にメールを送信する代わりに **Letter Opener Web** を使用してメールをブラウザで確認できます。

## 使い方

### 1. 新規アカウント登録
1. `http://localhost:3000/users/sign_up` にアクセス
2. メールアドレスとパスワードを入力して「アカウントを作成」をクリック
3. 「確認メールを送信しました。メール内のリンクをクリックしてアカウントを有効化してください。」というメッセージが表示されます

### 2. 送信されたメールを確認
1. ブラウザで `http://localhost:3000/letter_opener` にアクセス
2. 送信されたメール一覧が表示されます
3. 最新のメール（確認メール）をクリック
4. メール本文に表示されている「メールアドレスを確認する」リンクをクリック
5. アカウントが有効化され、ログイン可能になります

### 3. メール一覧の確認
- すべての送信メール（確認メール、パスワードリセットメールなど）が `http://localhost:3000/letter_opener` で確認できます
- メールは実際には送信されず、ブラウザで確認できるだけです

## 設定内容

### `config/environments/development.rb`
```ruby
config.action_mailer.delivery_method = :letter_opener_web
config.action_mailer.perform_deliveries = true
config.action_mailer.raise_delivery_errors = true
config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
```

### `config/routes.rb`
```ruby
mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
```

## トラブルシューティング

### メールが表示されない場合
1. Railsサーバーを再起動してください
   ```bash
   # Ctrl+C でサーバーを停止
   bin/dev
   ```

2. キャッシュをクリアしてください
   ```bash
   bin/rails tmp:clear
   ```

### テストユーザーを削除したい場合
```bash
bin/rails runner 'User.find_by(email: "your@email.com")&.destroy'
```

または、Railsコンソールで：
```bash
bin/rails console
> User.find_by(email: "your@email.com")&.destroy
> exit
```

## 本番環境について

本番環境では、実際のSMTPサーバー（Gmail、SendGrid、Amazon SESなど）を設定して、実際にメールを送信する必要があります。

`config/environments/production.rb` で適切なメール配信設定を行ってください。
