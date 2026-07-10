# Heroku デプロイガイド

## 📋 目次
1. [事前準備](#事前準備)
2. [画像ストレージの選択](#画像ストレージの選択)
3. [開発環境から本番環境への設定変更](#開発環境から本番環境への設定変更)
4. [Herokuデプロイ手順](#herokuデプロイ手順)
5. [デプロイ後の確認](#デプロイ後の確認)

---

## 事前準備

### 1. Heroku CLIのインストール
```bash
# macOSの場合
brew tap heroku/brew && brew install heroku

# インストール確認
heroku --version
```

### 2. Herokuログイン
```bash
heroku login
```

### 3. 必要な環境変数の確認
以下の環境変数を準備してください：

**必須:**
- `OPENAI_API_KEY` - OpenAI API キー
- `LINE_CHANNEL_TOKEN` - LINE Messaging API チャネルトークン
- `LINE_CHANNEL_SECRET` - LINE Messaging API チャネルシークレット
- `LINE_LOGIN_CHANNEL_ID` - LINE Login チャネルID
- `LINE_LOGIN_CHANNEL_SECRET` - LINE Login チャネルシークレット
- `RAILS_MASTER_KEY` - Rails credentials暗号化キー（`config/master.key`の内容）

**オプション:**
- `LINE_QR_CODE_IMAGE` - LINE友だち追加QRコード画像パス
- `LINE_ADD_FRIEND_URL` - LINE友だち追加URL
- `LINE_NOTIFY_CLIENT_ID` - LINE Notify クライアントID
- `LINE_NOTIFY_CLIENT_SECRET` - LINE Notify クライアントシークレット

---

## 画像ストレージの選択

### 現状分析
- **使用状況**: PDFファイル（レポートテンプレート）のみActive Storage使用
- **Heroku制限**: ファイルシステムは一時的（dynoが再起動すると消える）

### 推奨オプション

#### オプション1: AWS S3（推奨）
**メリット:**
- 安定性が高い
- 大量のファイルに対応可能
- Rails標準サポート

**コスト:**
- ストレージ: $0.023/GB/月（最初の50TB）
- リクエスト: $0.0004/1,000 PUT、$0.0004/10,000 GET
- **目安**: 100ファイル（5GB）で月額 $0.12〜0.50程度

**セットアップ:**
1. AWS S3バケット作成
2. IAMユーザー作成（S3アクセス権限）
3. 環境変数設定（後述）

#### オプション2: Cloudinary（画像が少ない場合）
**メリット:**
- セットアップ簡単
- 無料枠あり（月25クレジット、ストレージ25GB、帯域幅25GB）
- 画像最適化機能

**コスト:**
- 無料枠で十分カバー可能（小規模サイト）

**デメリット:**
- PDFの扱いがS3より少し複雑

### 決定基準
- **ユーザー数 < 100、PDFファイル < 50**: Cloudinary無料枠で十分
- **ユーザー数 > 100、または拡張予定**: AWS S3推奨

---

## 開発環境から本番環境への設定変更

### 1. Gemfileの更新

```ruby
# 本番環境用のgem追加
group :production do
  # AWS S3を使用する場合
  gem "aws-sdk-s3", require: false
  
  # または Cloudinaryを使用する場合
  # gem "cloudinary"
end
```

実行:
```bash
bundle install
```

### 2. config/storage.yml に本番用設定追加

**AWS S3の場合:**
```yaml
# config/storage.yml に追加
amazon:
  service: S3
  access_key_id: <%= ENV['AWS_ACCESS_KEY_ID'] %>
  secret_access_key: <%= ENV['AWS_SECRET_ACCESS_KEY'] %>
  region: <%= ENV['AWS_REGION'] || 'ap-northeast-1' %>  # 東京リージョン
  bucket: <%= ENV['AWS_S3_BUCKET'] %>
```

**Cloudinaryの場合:**
```yaml
# config/storage.yml に追加
cloudinary:
  service: Cloudinary
  cloud_name: <%= ENV['CLOUDINARY_CLOUD_NAME'] %>
  api_key: <%= ENV['CLOUDINARY_API_KEY'] %>
  api_secret: <%= ENV['CLOUDINARY_API_SECRET'] %>
```

### 3. config/environments/production.rb の更新

```ruby
# config/environments/production.rb

# Active Storageの設定変更（21行目付近）
# 変更前: config.active_storage.service = :local
# 変更後:
config.active_storage.service = :amazon  # または :cloudinary

# メール送信設定（必須）
config.action_mailer.raise_delivery_errors = true
config.action_mailer.delivery_method = :smtp
config.action_mailer.perform_deliveries = true
config.action_mailer.default_url_options = { 
  host: ENV['APP_HOST'] || 'your-app-name.herokuapp.com',
  protocol: 'https'
}

# SendGridの設定（Herokuアドオン使用の場合）
config.action_mailer.smtp_settings = {
  address: 'smtp.sendgrid.net',
  port: 587,
  domain: ENV['APP_HOST'] || 'herokuapp.com',
  user_name: ENV['SENDGRID_USERNAME'],
  password: ENV['SENDGRID_PASSWORD'],
  authentication: :plain,
  enable_starttls_auto: true
}

# ホスト設定（75行目付近のコメントアウトを解除）
config.hosts = [
  ENV['APP_HOST'] || 'your-app-name.herokuapp.com',
  /.*\.herokuapp\.com/  # Herokuのサブドメイン全て許可
]

# ログレベル（必要に応じて）
config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
```

### 4. Procfile作成（本番用）

```bash
# Procfile（Procfile.devではなく）
web: bundle exec puma -C config/puma.rb
worker: bundle exec rake solid_queue:start
```

ファイル作成:
```bash
cat > Procfile << 'EOF'
web: bundle exec puma -C config/puma.rb
worker: bundle exec rake solid_queue:start
EOF
```

### 5. config/puma.rb の確認

```ruby
# config/puma.rb
# 既存のままでOKですが、以下を確認

# Herokuは PORT 環境変数を設定
port ENV.fetch("PORT") { 3000 }

# ワーカー数（Herokuのdynoタイプに応じて調整）
workers ENV.fetch("WEB_CONCURRENCY") { 2 }

# スレッド数
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count
```

### 6. database.yml の確認

```yaml
# config/database.yml の production セクション
production:
  <<: *default
  # HerokuはDATABASE_URLを自動設定するため、これだけでOK
  url: <%= ENV['DATABASE_URL'] %>
```

---

## Herokuデプロイ手順

### ステップ1: Herokuアプリ作成

```bash
# アプリ作成（東京リージョン推奨）
heroku create your-app-name --region ap

# または自動命名
heroku create --region ap

# Git remoteの確認
git remote -v  # heroku というremoteが追加される
```

### ステップ2: PostgreSQLアドオン追加

```bash
# Hobby Dev（無料）プラン
heroku addons:create heroku-postgresql:essential-0

# データベースの確認
heroku pg:info
```

### ステップ3: Redisアドオン追加（Solid Queue用）

```bash
# Hobby Dev（無料）プラン
heroku addons:create heroku-redis:mini

# Redis接続確認
heroku redis:info
```

### ステップ4: 環境変数の設定

```bash
# Rails Master Key
heroku config:set RAILS_MASTER_KEY=$(cat config/master.key)

# OpenAI
heroku config:set OPENAI_API_KEY=your_openai_api_key

# LINE Messaging API
heroku config:set LINE_CHANNEL_TOKEN=your_line_channel_token
heroku config:set LINE_CHANNEL_SECRET=your_line_channel_secret

# LINE Login
heroku config:set LINE_LOGIN_CHANNEL_ID=your_line_login_channel_id
heroku config:set LINE_LOGIN_CHANNEL_SECRET=your_line_login_channel_secret

# AWS S3（S3使用の場合）
heroku config:set AWS_ACCESS_KEY_ID=your_aws_access_key
heroku config:set AWS_SECRET_ACCESS_KEY=your_aws_secret_key
heroku config:set AWS_REGION=ap-northeast-1
heroku config:set AWS_S3_BUCKET=your-bucket-name

# Cloudinary（Cloudinary使用の場合）
# heroku config:set CLOUDINARY_CLOUD_NAME=your_cloud_name
# heroku config:set CLOUDINARY_API_KEY=your_api_key
# heroku config:set CLOUDINARY_API_SECRET=your_api_secret

# アプリホスト名
heroku config:set APP_HOST=your-app-name.herokuapp.com

# LINE オプション設定
heroku config:set LINE_ADD_FRIEND_URL=https://line.me/R/ti/p/@your-line-id
heroku config:set LINE_QR_CODE_IMAGE=M_gainfriends_2dbarcodes_BW.png

# 環境変数の確認
heroku config
```

### ステップ5: SendGridアドオン追加（メール送信用）

```bash
# Starter（無料）プラン - 1日400通まで
heroku addons:create sendgrid:starter

# SendGridの認証情報は自動設定される
heroku config:get SENDGRID_USERNAME
heroku config:get SENDGRID_PASSWORD
```

### ステップ6: Buildpacksの設定

```bash
# Node.js buildpack（Tailwind CSS用）
heroku buildpacks:add heroku/nodejs

# Ruby buildpack
heroku buildpacks:add heroku/ruby

# 確認
heroku buildpacks
```

### ステップ7: デプロイ実行

```bash
# コミット確認
git status
git add .
git commit -m "Prepare for Heroku deployment"

# Herokuにpush（自動デプロイ開始）
git push heroku main

# または masterブランチの場合
# git push heroku master
```

### ステップ8: データベースマイグレーション

```bash
# マイグレーション実行
heroku run rails db:migrate

# シード（必要な場合）
heroku run rails db:seed
```

### ステップ9: Dynoの起動確認

```bash
# Webとworkerが起動しているか確認
heroku ps

# workerが起動していない場合
heroku ps:scale worker=1
```

---

## デプロイ後の確認

### 1. アプリの動作確認

```bash
# ブラウザで開く
heroku open

# ログ確認
heroku logs --tail

# エラーがある場合
heroku logs --tail --source app
```

### 2. LINE Webhook URLの更新

**LINE Messaging API:**
1. LINE Developersコンソールにログイン
2. あなたのチャネルを選択
3. Messaging API設定タブ
4. Webhook URL: `https://your-app-name.herokuapp.com/line_webhooks`
5. 「検証」ボタンで確認
6. 「Webhookの利用」をONに

**LINE Login:**
1. LINE Developersコンソール
2. LINE Loginチャネルを選択
3. Callback URL: `https://your-app-name.herokuapp.com/line_login/callback`

### 3. メール送信テスト

```bash
# Railsコンソールで確認
heroku run rails console

# コンソール内で
user = User.first
# Deviseの確認メール再送信などでテスト
```

### 4. ファイルアップロードテスト
- レポートテンプレートのPDFアップロードが正常に動作するか確認
- S3/Cloudinaryにファイルが保存されているか確認

### 5. パフォーマンス確認

```bash
# メトリクス確認
heroku metrics

# データベースの状態
heroku pg:info

# Redis の状態
heroku redis:info
```

---

## トラブルシューティング

### エラー: Application error (H10)
```bash
# ログ確認
heroku logs --tail

# データベース接続確認
heroku run rails db:migrate:status

# 環境変数確認
heroku config
```

### Assets（CSS/JS）が読み込まれない
```bash
# assetsのプリコンパイル（自動で行われるはずだが）
heroku run rails assets:precompile

# または、再デプロイ
git commit --allow-empty -m "Rebuild assets"
git push heroku main
```

### Solid Queue / Jobsが動かない
```bash
# worker dynoが起動しているか確認
heroku ps

# 起動していない場合
heroku ps:scale worker=1

# ログ確認
heroku logs --tail --dyno worker
```

### ファイルアップロードが失敗
```bash
# S3の環境変数確認
heroku config:get AWS_ACCESS_KEY_ID
heroku config:get AWS_SECRET_ACCESS_KEY
heroku config:get AWS_S3_BUCKET

# IAMポリシー確認（AWS Console）
# バケットポリシー確認（AWS Console）
```

---

## 推奨: 本番環境の監視設定

### 1. Herokuアドオンの追加

```bash
# NewRelic（APM - パフォーマンス監視）無料プラン
heroku addons:create newrelic:wayne

# Papertrail（ログ管理）無料プラン
heroku addons:create papertrail:choklad
```

### 2. 定期バックアップ

```bash
# データベースの手動バックアップ
heroku pg:backups:capture

# 自動バックアップ（有料プラン）
heroku addons:create heroku-postgresql:standard-0 --as DATABASE --backup-retention-period=7
```

---

## コスト見積もり（月額）

### 最小構成（スタートアップ向け）
- **Dyno**: Eco ($5/月) - webとworkerで合計1つ
- **PostgreSQL**: Essential-0 ($5/月) - 10M rows
- **Redis**: Mini ($3/月) - 25MB
- **SendGrid**: Starter (無料) - 1日400通
- **S3**: 〜$1/月（5GB、少量リクエスト）
- **合計**: 約 $14/月

### 推奨構成（中規模サイト）
- **Dyno**: Basic ($7×2 = $14/月) - webとworker各1つ
- **PostgreSQL**: Standard-0 ($50/月) - バックアップ付き
- **Redis**: Premium-0 ($15/月) - 100MB
- **SendGrid**: Essentials ($19.95/月) - 1日40,000通
- **S3**: 〜$5/月（50GB）
- **合計**: 約 $103/月

---

## 次のステップ

1. **カスタムドメイン設定**: `heroku domains:add www.yourdomain.com`
2. **SSL証明書**: Heroku自動提供（Let's Encrypt）
3. **CD/CI設定**: GitHub Actionsとの連携
4. **Staging環境**: `heroku create your-app-staging --remote staging`

---

## 参考リンク

- [Heroku Dev Center - Rails](https://devcenter.heroku.com/categories/ruby-support)
- [Active Storage on Heroku](https://devcenter.heroku.com/articles/active-storage-on-heroku)
- [Heroku Postgres](https://devcenter.heroku.com/articles/heroku-postgresql)
- [SendGrid on Heroku](https://devcenter.heroku.com/articles/sendgrid)
