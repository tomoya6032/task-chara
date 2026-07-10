# Heroku デプロイ クイックスタートガイド

このガイドでは、最短でHerokuにデプロイする手順を示します。
詳細は `HEROKU_DEPLOY_GUIDE.md` を参照してください。

## 📋 事前準備チェックリスト

### 必須項目
- [ ] Heroku CLIがインストール済み（`heroku --version`で確認）
- [ ] Herokuアカウントにログイン済み（`heroku login`）
- [ ] `config/master.key` ファイルが存在する
- [ ] 以下の環境変数の値を準備済み：
  - [ ] `OPENAI_API_KEY`
  - [ ] `LINE_CHANNEL_TOKEN`
  - [ ] `LINE_CHANNEL_SECRET`
  - [ ] `LINE_LOGIN_CHANNEL_ID`
  - [ ] `LINE_LOGIN_CHANNEL_SECRET`

### AWS S3使用の場合（推奨）
- [ ] S3バケット作成済み
- [ ] IAMユーザー作成済み（S3アクセス権限付与）
- [ ] 以下の値を準備済み：
  - [ ] `AWS_ACCESS_KEY_ID`
  - [ ] `AWS_SECRET_ACCESS_KEY`
  - [ ] `AWS_REGION`（例: ap-northeast-1）
  - [ ] `AWS_S3_BUCKET`（バケット名）

---

## 🚀 デプロイ手順（10分）

### 1. Gemのインストール

```bash
bundle install
```

### 2. Herokuアプリ作成

```bash
# アプリ作成（東京リージョン）
heroku create your-app-name --region ap

# 作成されたアプリ名を確認
heroku apps:info
```

**重要**: アプリ名をメモしておく（例: `your-app-name.herokuapp.com`）

### 3. アドオン追加

```bash
# PostgreSQL（必須）
heroku addons:create heroku-postgresql:essential-0

# Redis（Solid Queue用、必須）
heroku addons:create heroku-redis:mini

# SendGrid（メール送信、推奨）
heroku addons:create sendgrid:starter
```

### 4. 環境変数設定

```bash
# Rails Master Key（必須）
heroku config:set RAILS_MASTER_KEY=$(cat config/master.key)

# OpenAI API Key（必須）
heroku config:set OPENAI_API_KEY=your_openai_api_key_here

# LINE Messaging API（必須）
heroku config:set LINE_CHANNEL_TOKEN=your_line_channel_token_here
heroku config:set LINE_CHANNEL_SECRET=your_line_channel_secret_here

# LINE Login（必須）
heroku config:set LINE_LOGIN_CHANNEL_ID=your_line_login_channel_id_here
heroku config:set LINE_LOGIN_CHANNEL_SECRET=your_line_login_channel_secret_here

# AWS S3（S3使用の場合）
heroku config:set AWS_ACCESS_KEY_ID=your_aws_access_key_here
heroku config:set AWS_SECRET_ACCESS_KEY=your_aws_secret_key_here
heroku config:set AWS_REGION=ap-northeast-1
heroku config:set AWS_S3_BUCKET=your-bucket-name

# アプリホスト名（必須）- あなたのアプリ名に置き換える
heroku config:set APP_HOST=your-app-name.herokuapp.com

# 設定確認
heroku config
```

### 5. Buildpacks設定

```bash
heroku buildpacks:add heroku/nodejs
heroku buildpacks:add heroku/ruby
```

### 6. デプロイ

```bash
# 変更をコミット
git add .
git commit -m "Configure for Heroku deployment"

# Herokuにプッシュ（デプロイ開始）
git push heroku main

# または masterブランチの場合
# git push heroku master
```

### 7. データベースセットアップ

```bash
# マイグレーション実行
heroku run rails db:migrate

# 必要に応じてシード実行
# heroku run rails db:seed
```

### 8. Dyno起動

```bash
# Worker dynoを起動（ジョブ処理用）
heroku ps:scale worker=1

# 状態確認
heroku ps
```

### 9. アプリを開く

```bash
# ブラウザで開く
heroku open

# ログ確認
heroku logs --tail
```

---

## ⚙️ LINE設定の更新

デプロイ後、LINEの設定を更新する必要があります。

### LINE Messaging API Webhook URL

1. [LINE Developers Console](https://developers.line.biz/console/) にログイン
2. あなたのチャネルを選択
3. **Messaging API設定** タブを開く
4. **Webhook URL** に以下を設定:
   ```
   https://your-app-name.herokuapp.com/line_webhooks
   ```
5. **検証** ボタンをクリックして確認
6. **Webhookの利用** を **ON** にする

### LINE Login Callback URL

1. [LINE Developers Console](https://developers.line.biz/console/) にログイン
2. LINE Login チャネルを選択
3. **Callback URL** に以下を設定:
   ```
   https://your-app-name.herokuapp.com/line_login/callback
   ```
4. 保存

---

## ✅ デプロイ後の確認

### 1. アプリの動作確認

```bash
# アプリを開く
heroku open

# ログイン画面が表示されるか確認
```

### 2. ログ確認

```bash
# リアルタイムログ表示
heroku logs --tail

# エラーがある場合は確認
heroku logs --tail --source app
```

### 3. 基本機能テスト

- [ ] ユーザー登録ができるか
- [ ] ログインができるか
- [ ] メール送信が動作するか（確認メールなど）
- [ ] タスク作成ができるか
- [ ] カレンダー表示が正常か
- [ ] LINE連携ボタンが動作するか

### 4. ファイルアップロードテスト（S3使用の場合）

- [ ] レポートテンプレートのPDFアップロードができるか
- [ ] S3にファイルが保存されているか（AWSコンソールで確認）

---

## 🔧 トラブルシューティング

### Application error (H10)

```bash
# ログ確認
heroku logs --tail

# データベース接続確認
heroku run rails db:migrate:status
```

### Assets（CSS/JS）が読み込まれない

```bash
# 再デプロイ
git commit --allow-empty -m "Rebuild assets"
git push heroku main
```

### メールが送信されない

```bash
# SendGrid設定確認
heroku config:get SENDGRID_USERNAME
heroku config:get SENDGRID_PASSWORD

# SendGridダッシュボードで送信状況確認
heroku addons:open sendgrid
```

### LINE Webhookが動作しない

```bash
# ログ確認
heroku logs --tail | grep line

# 環境変数確認
heroku config:get LINE_CHANNEL_TOKEN
heroku config:get LINE_CHANNEL_SECRET
```

---

## 📊 本番環境の監視

### リソース使用状況

```bash
# メトリクス確認
heroku metrics

# データベース状態
heroku pg:info

# Redis状態
heroku redis:info
```

### ログ管理

```bash
# 最近のログ表示
heroku logs --tail

# エラーログのみ表示
heroku logs --tail | grep ERROR
```

---

## 💰 コスト見積もり

### 最小構成（月額 約$14）
- Dyno: Eco ($5) - web + worker
- PostgreSQL: Essential-0 ($5)
- Redis: Mini ($3)
- SendGrid: Starter (無料)
- S3: 〜$1

### 推奨構成（月額 約$103）
- Dyno: Basic ($14) - web + worker各1
- PostgreSQL: Standard-0 ($50) - バックアップ付き
- Redis: Premium-0 ($15)
- SendGrid: Essentials ($19.95)
- S3: 〜$5

---

## 🎯 次のステップ

1. **カスタムドメイン設定**
   ```bash
   heroku domains:add www.yourdomain.com
   ```

2. **定期バックアップ**
   ```bash
   heroku pg:backups:schedule DATABASE_URL --at '02:00 Asia/Tokyo'
   ```

3. **監視ツール追加**
   ```bash
   heroku addons:create papertrail:choklad  # ログ管理（無料）
   ```

4. **Staging環境作成**
   ```bash
   heroku create your-app-staging --remote staging
   ```

---

## 📚 参考資料

- [HEROKU_DEPLOY_GUIDE.md](./HEROKU_DEPLOY_GUIDE.md) - 詳細なデプロイガイド
- [Heroku Dev Center](https://devcenter.heroku.com/)
- [Heroku Postgres](https://devcenter.heroku.com/articles/heroku-postgresql)
- [Active Storage on Heroku](https://devcenter.heroku.com/articles/active-storage-on-heroku)

---

## 🆘 サポート

問題が発生した場合：

1. ログを確認: `heroku logs --tail`
2. 環境変数を確認: `heroku config`
3. データベース状態を確認: `heroku pg:info`
4. Heroku Status確認: https://status.heroku.com/

それでも解決しない場合は、詳細なデプロイガイド（HEROKU_DEPLOY_GUIDE.md）を参照してください。
