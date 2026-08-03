# 支援報告書機能 - Heroku本番環境セットアップガイド

本番環境（Heroku）で支援報告書機能を動作させるための設定手順です。

## 📋 問題の原因

### 1. **Active Storage（ファイルストレージ）の設定不足**
- 本番環境ではAWS S3を使用する設定だが、環境変数が未設定
- Herokuのローカルファイルシステムは一時的（Dyno再起動で消える）
- PDFテンプレートファイルが保存されない、または消失する

### 2. **ImageMagickの不在**
- PDF→画像変換に必要なImageMagickがHerokuにインストールされていない
- `mini_magick` gemは ImageMagick に依存

### 3. **OpenAI API Key の未設定**
- AI生成機能に必須の `OPENAI_API_KEY` 環境変数が未設定

### 4. **Solid Queue Workerの未起動**
- バックグラウンドジョブ処理用のworkerプロセスがスケールされていない可能性
- ジョブが実行されない

### 5. **RAILS_MASTER_KEY の未設定**
- 本番環境での credentials 読み込みに必要

---

## 🔧 必須設定手順

### ステップ1: Heroku CLIにログイン

```bash
heroku login
```

### ステップ2: アプリ名を確認（以下の `your-app-name` を実際のアプリ名に置き換え）

```bash
heroku apps
```

---

### ステップ3: 環境変数の設定

#### A. OpenAI API Key（必須）

```bash
heroku config:set OPENAI_API_KEY=your_openai_api_key_here --app your-app-name
```

**取得方法:**
- OpenAIのダッシュボード (https://platform.openai.com/api-keys) でAPIキーを作成
- `sk-proj-` で始まるキーをコピー

---

#### B. AWS S3設定（PDFテンプレート保存に必須）

```bash
# AWS認証情報
heroku config:set AWS_ACCESS_KEY_ID=your_aws_access_key_here --app your-app-name
heroku config:set AWS_SECRET_ACCESS_KEY=your_aws_secret_key_here --app your-app-name

# S3バケット情報
heroku config:set AWS_S3_BUCKET=your-bucket-name --app your-app-name
heroku config:set AWS_REGION=ap-northeast-1 --app your-app-name
```

**AWS S3の準備手順:**

1. **AWSアカウントでS3バケットを作成**
   ```
   - AWSコンソール → S3 → 「バケットを作成」
   - バケット名: 例 `taskcharacter-production` (グローバルで一意な名前)
   - リージョン: ap-northeast-1 (東京)
   - パブリックアクセス: すべてブロック（デフォルト）
   ```

2. **IAMユーザーを作成してアクセスキーを取得**
   ```
   - AWSコンソール → IAM → ユーザー → 「ユーザーを作成」
   - ユーザー名: 例 `taskcharacter-s3-user`
   - 「プログラムによるアクセス」を選択
   - ポリシー: 「AmazonS3FullAccess」を付与（または下記のカスタムポリシー）
   - アクセスキーIDとシークレットアクセスキーをメモ
   ```

3. **（推奨）カスタムIAMポリシー（最小権限）**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:PutObject",
           "s3:GetObject",
           "s3:DeleteObject",
           "s3:ListBucket"
         ],
         "Resource": [
           "arn:aws:s3:::your-bucket-name/*",
           "arn:aws:s3:::your-bucket-name"
         ]
       }
     ]
   }
   ```

---

#### C. RAILS_MASTER_KEY（credentials使用時に必須）

```bash
# ローカルの config/master.key の内容をコピー
cat config/master.key

# Herokuに設定
heroku config:set RAILS_MASTER_KEY=your_master_key_here --app your-app-name
```

**注意:** `config/master.key` は `.gitignore` に含まれているため、リポジトリにはコミットされていません。ローカルのファイルから取得してください。

---

### ステップ4: ImageMagick Buildpackの追加

```bash
# Buildpackを追加（PDFから画像への変換に必要）
heroku buildpacks:add --index 1 https://github.com/brandoncc/heroku-buildpack-vips --app your-app-name
heroku buildpacks:add --index 2 https://github.com/DarthSim/heroku-buildpack-imagemagick --app your-app-name

# 現在のBuildpackを確認
heroku buildpacks --app your-app-name
```

**期待される出力:**
```
=== your-app-name Buildpack URLs
1. https://github.com/brandoncc/heroku-buildpack-vips
2. https://github.com/DarthSim/heroku-buildpack-imagemagick
3. heroku/ruby
```

---

### ステップ5: Solid Queue Workerのスケール設定

```bash
# Workerプロセスを1台起動（バックグラウンドジョブ処理用）
heroku ps:scale worker=1 --app your-app-name

# プロセスの状態を確認
heroku ps --app your-app-name
```

**期待される出力:**
```
=== web (Standard-1X): bundle exec puma -C config/puma.rb
web.1: up 2023/12/01 10:00:00 +0900 (~ 1h ago)

=== worker (Standard-1X): bundle exec rake solid_queue:start
worker.1: up 2023/12/01 10:00:00 +0900 (~ 1h ago)
```

**注意:** Workerプロセスは追加料金が発生します（Standard-1X: 約$25/月）。

---

### ステップ6: アプリケーションの再デプロイ

```bash
# 変更を適用するために再デプロイ（Buildpackの追加後は必須）
git commit --allow-empty -m "Rebuild with ImageMagick buildpack"
git push heroku main

# または、再起動のみ
heroku restart --app your-app-name
```

---

## ✅ 設定確認

### 環境変数の確認

```bash
heroku config --app your-app-name
```

**必須の環境変数:**
- ✅ `OPENAI_API_KEY`
- ✅ `AWS_ACCESS_KEY_ID`
- ✅ `AWS_SECRET_ACCESS_KEY`
- ✅ `AWS_S3_BUCKET`
- ✅ `AWS_REGION`
- ✅ `RAILS_MASTER_KEY`

---

### ログの確認

```bash
# リアルタイムログを表示
heroku logs --tail --app your-app-name

# 支援報告書関連のログのみ表示
heroku logs --tail --app your-app-name | grep "SupportReport"
```

---

## 🧪 動作テスト手順

### 1. テンプレートの作成テスト

```
1. 本番環境にログイン: https://your-app-name.herokuapp.com
2. 支援報告書 → テンプレート管理 → 新規テンプレート作成
3. PDFファイルをアップロード
4. 保存後、テンプレートが正しく保存されるか確認
```

**期待される動作:**
- ✅ PDFアップロードが成功
- ✅ バックグラウンドでPDF解析ジョブが実行される
- ✅ テンプレートの構造が自動抽出される
- ✅ S3にPDFファイルが保存される

---

### 2. 支援報告書のAI生成テスト

```
1. 日報データを複数件作成（対象期間に合わせて）
2. 支援報告書 → 新規作成
3. 対象期間を選択、テンプレートを選択
4. 生成ボタンをクリック
5. バックグラウンドで生成処理が実行される
```

**期待される動作:**
- ✅ 「支援報告書の生成を開始しました」のメッセージが表示
- ✅ ステータスが「生成中」に変わる
- ✅ 数秒〜数十秒後、ステータスが「完成」に変わる
- ✅ AI生成された報告書の内容が表示される

---

### 3. ログでの確認

```bash
# 支援報告書生成ログ
heroku logs --tail --app your-app-name | grep "SupportReportGeneratorService"

# ジョブ実行ログ
heroku logs --tail --app your-app-name | grep "GenerateSupportReportJob"

# OpenAI API呼び出しログ
heroku logs --tail --app your-app-name | grep "OpenAI"
```

---

## ⚠️ トラブルシューティング

### 問題1: テンプレートがアップロードできない

**症状:**
- PDFアップロードでエラーが発生
- 「ファイルが保存されませんでした」

**原因と対処:**
```bash
# AWS S3設定を確認
heroku config:get AWS_ACCESS_KEY_ID --app your-app-name
heroku config:get AWS_SECRET_ACCESS_KEY --app your-app-name
heroku config:get AWS_S3_BUCKET --app your-app-name

# S3バケットが存在するか確認（AWS コンソール）
# IAMユーザーの権限を確認
```

---

### 問題2: PDF構造解析が動作しない

**症状:**
- テンプレート作成後、contentカラムが空のまま
- ログに「MiniMagick gem not available」

**原因と対処:**
```bash
# ImageMagick Buildpackが追加されているか確認
heroku buildpacks --app your-app-name

# なければ追加して再デプロイ
heroku buildpacks:add https://github.com/DarthSim/heroku-buildpack-imagemagick --app your-app-name
git commit --allow-empty -m "Add ImageMagick buildpack"
git push heroku main
```

---

### 問題3: AI生成が実行されない

**症状:**
- 支援報告書のステータスが「下書き」のまま
- 「生成中」に変わらない

**原因と対処:**
```bash
# Workerプロセスが起動しているか確認
heroku ps --app your-app-name

# Workerが0台の場合は起動
heroku ps:scale worker=1 --app your-app-name

# Solid Queueのジョブを確認（Rails Console）
heroku run rails console --app your-app-name
> SolidQueue::Job.count
> SolidQueue::Job.last(5)
```

---

### 問題4: OpenAI APIエラー

**症状:**
- ログに「OpenAI API error: Unauthorized」
- ステータスが「エラー」になる

**原因と対処:**
```bash
# API Keyが設定されているか確認
heroku config:get OPENAI_API_KEY --app your-app-name

# API Keyが有効か確認（OpenAI Dashboard）
# https://platform.openai.com/api-keys

# API利用料金の残高を確認
# https://platform.openai.com/account/billing/overview
```

---

## 💰 コスト見積もり

### Heroku

| リソース | プラン | 月額料金（概算） |
|---------|--------|----------------|
| Web Dyno | Standard-1X | 無料〜$25 |
| Worker Dyno | Standard-1X | $25 |
| PostgreSQL | Standard-0 | $50 |
| **合計** | | **$75〜$100/月** |

### AWS S3

| 項目 | 使用量（想定） | 月額料金（概算） |
|------|---------------|----------------|
| ストレージ | 1GB | $0.025 |
| リクエスト | 10,000件 | $0.05 |
| データ転送 | 1GB | $0.09 |
| **合計** | | **$0.16/月** |

### OpenAI API

| モデル | 使用量（想定） | 月額料金（概算） |
|--------|---------------|----------------|
| GPT-4o | 100リクエスト/月 | $3〜$5 |
| GPT-4o (Vision) | 10画像解析/月 | $0.5〜$1 |
| **合計** | | **$3.5〜$6/月** |

**総合計: 約$79〜$106/月**

---

## 📚 参考リンク

- [Heroku Buildpacks](https://devcenter.heroku.com/articles/buildpacks)
- [Active Storage on AWS S3](https://edgeguides.rubyonrails.org/active_storage_overview.html#s3-service-amazon-s3-and-s3-compatible-apis)
- [OpenAI API Documentation](https://platform.openai.com/docs/api-reference)
- [Solid Queue on Heroku](https://github.com/basecamp/solid_queue#deployment)

---

## ✅ チェックリスト

設定完了後、以下を確認してください：

- [ ] `OPENAI_API_KEY` が設定されている
- [ ] `AWS_ACCESS_KEY_ID` が設定されている
- [ ] `AWS_SECRET_ACCESS_KEY` が設定されている
- [ ] `AWS_S3_BUCKET` が設定されている
- [ ] `AWS_REGION` が設定されている
- [ ] `RAILS_MASTER_KEY` が設定されている
- [ ] ImageMagick Buildpackが追加されている
- [ ] Workerプロセスが1台起動している
- [ ] テンプレートのPDFアップロードが成功する
- [ ] PDF構造解析が実行される（contentカラムに内容が入る）
- [ ] 支援報告書のAI生成が成功する

---

**設定完了後の確認コマンド:**

```bash
# 全環境変数を確認
heroku config --app your-app-name

# Buildpackを確認
heroku buildpacks --app your-app-name

# プロセスを確認
heroku ps --app your-app-name

# ログを確認
heroku logs --tail --app your-app-name
```
