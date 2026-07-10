# Heroku デプロイ準備 - 変更サマリー

このドキュメントは、Herokuデプロイのために行った変更をまとめたものです。

## 📁 作成されたファイル

### 1. `HEROKU_DEPLOY_GUIDE.md`
**目的**: Herokuデプロイの詳細ガイド  
**内容**:
- 事前準備（Heroku CLI、環境変数）
- 画像ストレージの選択（AWS S3 vs Cloudinary）
- 開発環境から本番環境への設定変更
- ステップバイステップのデプロイ手順
- トラブルシューティング
- コスト見積もり

### 2. `DEPLOY_QUICKSTART.md`
**目的**: 10分でデプロイするためのクイックスタートガイド  
**内容**:
- チェックリスト形式の事前準備
- 簡潔なデプロイ手順
- LINE設定の更新方法
- デプロイ後の確認項目

### 3. `Procfile`
**目的**: Herokuでのプロセス定義  
**内容**:
```
web: bundle exec puma -C config/puma.rb
worker: bundle exec rake solid_queue:start
```

---

## 🔧 変更されたファイル

### 1. `Gemfile`
**変更内容**: 本番環境用のgem追加

```ruby
group :production do
  # AWS S3 for Active Storage in production
  gem "aws-sdk-s3", require: false
end
```

**理由**: HerokuではActive StorageにAWS S3を使用するため

**次の手順**: `bundle install` を実行

---

### 2. `config/storage.yml`
**変更内容**: AWS S3設定を有効化

```yaml
amazon:
  service: S3
  access_key_id: <%= ENV['AWS_ACCESS_KEY_ID'] %>
  secret_access_key: <%= ENV['AWS_SECRET_ACCESS_KEY'] %>
  region: <%= ENV['AWS_REGION'] || 'ap-northeast-1' %>
  bucket: <%= ENV['AWS_S3_BUCKET'] %>
```

**理由**: 本番環境でS3を使用するため（環境変数から設定を読み込む）

---

### 3. `config/environments/production.rb`
**主な変更点**:

#### Active Storageの変更
```ruby
# 変更前
config.active_storage.service = :local

# 変更後
config.active_storage.service = :amazon
```

#### メール設定の追加
```ruby
config.action_mailer.raise_delivery_errors = true
config.action_mailer.delivery_method = :smtp
config.action_mailer.perform_deliveries = true

config.action_mailer.default_url_options = { 
  host: ENV['APP_HOST'] || 'localhost:3000',
  protocol: 'https'
}

config.action_mailer.smtp_settings = {
  address: 'smtp.sendgrid.net',
  port: 587,
  domain: ENV['APP_HOST'] || 'herokuapp.com',
  user_name: ENV['SENDGRID_USERNAME'],
  password: ENV['SENDGRID_PASSWORD'],
  authentication: :plain,
  enable_starttls_auto: true
}
```

#### ホスト設定の有効化
```ruby
config.hosts = [
  ENV['APP_HOST'],              # Your Heroku app domain
  /.*\.herokuapp\.com/,         # All Heroku subdomains
  "localhost"                   # For local testing
].compact

config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
```

**理由**: 
- S3でファイル保存
- SendGridでメール送信
- Herokuドメインを許可

---

### 4. `config/database.yml`
**変更内容**: Herokuの`DATABASE_URL`環境変数を使用

```yaml
production:
  primary: &primary_production
    <<: *default
    url: <%= ENV['DATABASE_URL'] %>
  cache:
    <<: *primary_production
    database: <%= ENV['DATABASE_URL'] %>_cache
    migrations_paths: db/cache_migrate
  queue:
    <<: *primary_production
    database: <%= ENV['DATABASE_URL'] %>_queue
    migrations_paths: db/queue_migrate
  cable:
    <<: *primary_production
    database: <%= ENV['DATABASE_URL'] %>_cable
    migrations_paths: db/cable_migrate
```

**理由**: HerokuがPostgreSQLを自動的に設定するため

---

### 5. `.env.example`
**変更内容**: 本番環境用の環境変数を追加

新しく追加された環境変数:
- `RAILS_MASTER_KEY`
- `APP_HOST`
- `LINE_LOGIN_CHANNEL_ID`
- `LINE_LOGIN_CHANNEL_SECRET`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `AWS_S3_BUCKET`
- `LINE_ADD_FRIEND_URL`
- `WEB_CONCURRENCY`
- `RAILS_MAX_THREADS`
- `RAILS_MIN_THREADS`
- `RAILS_LOG_LEVEL`

**理由**: デプロイ時に必要な環境変数のテンプレート提供

---

## 🔑 必要な環境変数まとめ

### 必須
1. `RAILS_MASTER_KEY` - `config/master.key`の内容
2. `APP_HOST` - Herokuアプリのドメイン（例: `your-app.herokuapp.com`）
3. `OPENAI_API_KEY` - OpenAI APIキー
4. `LINE_CHANNEL_TOKEN` - LINE Messaging APIトークン
5. `LINE_CHANNEL_SECRET` - LINE Messaging APIシークレット
6. `LINE_LOGIN_CHANNEL_ID` - LINE LoginチャネルID
7. `LINE_LOGIN_CHANNEL_SECRET` - LINE Loginシークレット

### S3使用の場合（推奨）
8. `AWS_ACCESS_KEY_ID` - AWS IAMアクセスキー
9. `AWS_SECRET_ACCESS_KEY` - AWS IAMシークレットキー
10. `AWS_REGION` - AWSリージョン（例: `ap-northeast-1`）
11. `AWS_S3_BUCKET` - S3バケット名

### オプション
12. `LINE_ADD_FRIEND_URL` - LINE友だち追加URL
13. `LINE_QR_CODE_IMAGE` - QRコード画像パス
14. `LINE_NOTIFY_CLIENT_ID` - LINE NotifyクライアントID
15. `LINE_NOTIFY_CLIENT_SECRET` - LINE Notifyシークレット

### Herokuが自動設定
- `DATABASE_URL` - PostgreSQL接続URL
- `REDIS_URL` - Redis接続URL
- `SENDGRID_USERNAME` - SendGridユーザー名
- `SENDGRID_PASSWORD` - SendGridパスワード
- `PORT` - アプリのポート番号

---

## 📝 デプロイ前の確認事項

### コード関連
- [x] Gemfileに`aws-sdk-s3`追加済み
- [x] Procfile作成済み
- [x] production.rb更新済み
- [x] storage.yml更新済み
- [x] database.yml更新済み
- [ ] `bundle install`実行
- [ ] 変更をgitにコミット

### AWS S3関連（S3使用の場合）
- [ ] S3バケット作成
- [ ] IAMユーザー作成
- [ ] S3アクセス権限付与
- [ ] アクセスキー発行

### LINE関連
- [ ] LINE Messaging APIチャネル作成済み
- [ ] LINE Loginチャネル作成済み
- [ ] 必要な認証情報を取得済み

### Heroku関連
- [ ] Heroku CLIインストール済み
- [ ] Herokuアカウント作成済み
- [ ] `heroku login`実行済み

---

## 🚀 次のステップ

### 1. Gemのインストール
```bash
bundle install
```

### 2. 変更をコミット
```bash
git add .
git commit -m "Configure for Heroku deployment"
```

### 3. デプロイ手順に従う

以下のいずれかのガイドに従ってデプロイしてください：

- **クイックスタート（10分）**: `DEPLOY_QUICKSTART.md`
- **詳細ガイド（初めての方）**: `HEROKU_DEPLOY_GUIDE.md`

---

## 💡 重要なポイント

### 画像ストレージについて

**推奨: AWS S3**
- Herokuのファイルシステムは一時的（再起動で消える）
- S3は永続的で信頼性が高い
- コストも低い（月$1程度から）

**代替: Cloudinary**
- セットアップが簡単
- 無料枠が大きい（小規模サイト向け）
- 画像最適化機能あり

### メール送信について

**推奨: SendGrid（Herokuアドオン）**
- 簡単にセットアップ可能
- 無料プラン: 1日400通
- Herokuが自動的に環境変数を設定

### データベースについて

**PostgreSQL（Herokuが自動設定）**
- 開発環境と同じPostgreSQLなので互換性良好
- Herokuが`DATABASE_URL`を自動設定
- バックアップ機能あり（有料プラン）

### ジョブ処理について

**Solid Queue + Redis**
- バックグラウンドジョブ処理
- Heroku Redisアドオン使用
- `worker` dynoで実行

---

## 🔍 トラブルシューティング参考

よくある問題と解決方法は以下を参照：
- `HEROKU_DEPLOY_GUIDE.md` のトラブルシューティングセクション
- `DEPLOY_QUICKSTART.md` のトラブルシューティングセクション

---

## 📞 サポート

質問や問題がある場合：
1. `heroku logs --tail`でログ確認
2. `heroku config`で環境変数確認
3. デプロイガイドのトラブルシューティングセクション参照
4. [Heroku Dev Center](https://devcenter.heroku.com/)で検索

---

**作成日**: 2026-06-30  
**対象環境**: Heroku（東京リージョン推奨）  
**Rails バージョン**: 8.0.4  
**Ruby バージョン**: 3.4.1  
**データベース**: PostgreSQL
