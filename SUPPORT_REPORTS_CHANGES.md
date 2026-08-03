# 支援報告書機能 - 本番環境対応の変更内容

## 📝 変更概要

開発環境で動作している支援報告書機能を、本番環境（Heroku）で正しく動作させるための修正を実施しました。

**変更日:** 2024年12月

**対応内容:**
1. 環境設定チェック機能の追加
2. エラーメッセージの改善
3. 包括的なセットアップガイドの作成
4. 診断・テストツールの追加

---

## 🔧 コード変更

### 1. SupportReportGeneratorService (app/services/support_report_generator_service.rb)

**変更内容:**
- OpenAI API Keyの存在チェックを追加
- 未設定時に明確なエラーメッセージを表示

**変更箇所:**
```ruby
def initialize(support_report, activity_ids: nil)
  # ... 既存のコード ...
  
  # OpenAI API Keyのチェック（新規追加）
  api_key = ENV["OPENAI_API_KEY"] || Rails.application.credentials.dig(:openai, :api_key) || ENV["OPENAI_ACCESS_TOKEN"]
  if api_key.blank?
    raise "OpenAI API Keyが設定されていません。環境変数OPENAI_API_KEYを設定してください。"
  end
  
  @client = OpenAI::Client.new
end
```

---

### 2. AnalyzePdfTemplateJob (app/jobs/analyze_pdf_template_job.rb)

**変更内容:**
- OpenAI API Keyの存在チェック
- ImageMagickのインストール確認
- Active Storageの設定警告
- 詳細なエラーメッセージとHeroku設定ガイド

**変更箇所:**
```ruby
def perform(template_id)
  Rails.logger.info "=== PDF Template Analysis Started ==="
  
  # 1. OpenAI API Keyのチェック（新規追加）
  api_key = ENV["OPENAI_API_KEY"] || ...
  if api_key.blank?
    Rails.logger.error "❌ OpenAI API Keyが設定されていません。"
    return
  end
  
  # 2. ImageMagickの可用性チェック（新規追加）
  begin
    require "mini_magick"
    MiniMagick::Tool::Convert.new { |c| c.version }
  rescue MiniMagick::Error => e
    Rails.logger.error "❌ ImageMagickがインストールされていません。"
    Rails.logger.error "   heroku buildpacks:add ..."
    return
  end
  
  # 3. Active Storageの設定チェック（新規追加）
  if Rails.env.production? && Rails.application.config.active_storage.service != :amazon
    Rails.logger.warn "⚠️ 本番環境ではAWS S3の使用を推奨します。"
  end
  
  # ... 既存の処理 ...
end
```

---

### 3. 診断Rakeタスク (lib/tasks/check_support_reports.rake)

**新規作成:**
- `bin/rails support_reports:check_config` - 設定診断タスク
- `bin/rails support_reports:test_generate` - テスト生成タスク（開発環境用）

**機能:**
- OpenAI API Keyの設定確認と接続テスト
- Active Storageの設定確認（S3 vs Local）
- AWS認証情報の確認
- ImageMagickのインストール確認
- Solid Queue Workerの状態確認
- ジョブキューの状態確認
- テンプレートの登録状況確認
- 詳細なエラー・警告レポート

**使用例:**
```bash
# ローカルで実行
bin/rails support_reports:check_config

# Herokuで実行
heroku run bin/rails support_reports:check_config --app your-app-name
```

---

## 📚 新規ドキュメント

### 1. HEROKU_SUPPORT_REPORTS_SETUP.md（詳細ガイド）

**内容:**
- 問題の原因の詳細説明
- 5つの必須設定手順
  1. Heroku CLIログイン
  2. 環境変数の設定（OpenAI, AWS S3, RAILS_MASTER_KEY）
  3. ImageMagick Buildpackの追加
  4. Solid Queue Workerのスケール設定
  5. 再デプロイと確認
- AWS S3バケットの作成手順
- IAMユーザーとアクセスキーの設定
- 詳細なトラブルシューティング
- コスト見積もり（Heroku + S3 + OpenAI）
- チェックリストと確認コマンド

**対象読者:** 詳細な設定手順を必要とする開発者

---

### 2. SUPPORT_REPORTS_QUICKSTART.md（クイックスタート）

**内容:**
- 最短5ステップでの設定完了
- コピー&ペーストで実行できるコマンド集
- シンプルな動作テスト手順
- よくあるエラーと即座の解決方法
- 設定確認チェックリスト
- コスト削減のヒント

**対象読者:** 迅速に設定を完了したい開発者

---

## 🎯 本番環境で必要な設定（まとめ）

### 必須環境変数

```bash
# 1. OpenAI API Key（必須）
heroku config:set OPENAI_API_KEY=sk-proj-... --app your-app-name

# 2. AWS S3認証情報（推奨 - ファイル保存）
heroku config:set AWS_ACCESS_KEY_ID=AKIA... --app your-app-name
heroku config:set AWS_SECRET_ACCESS_KEY=... --app your-app-name
heroku config:set AWS_S3_BUCKET=your-bucket-name --app your-app-name
heroku config:set AWS_REGION=ap-northeast-1 --app your-app-name

# 3. Rails Master Key（credentials使用時）
heroku config:set RAILS_MASTER_KEY=... --app your-app-name
```

### 必須Buildpack

```bash
heroku buildpacks:add https://github.com/DarthSim/heroku-buildpack-imagemagick --app your-app-name
```

### 必須プロセス

```bash
heroku ps:scale worker=1 --app your-app-name
```

---

## 📊 動作フロー

### テンプレート作成時

```
1. ユーザーがPDFをアップロード
   ↓
2. Active Storage → AWS S3に保存（本番環境）
   ↓
3. AnalyzePdfTemplateJob（バックグラウンド）
   ↓
4. PDFダウンロード → 画像変換（ImageMagick）
   ↓
5. OpenAI Vision API（gpt-4o）で構造解析
   ↓
6. テンプレートのcontentカラムに保存
```

### 支援報告書生成時

```
1. ユーザーが生成リクエスト
   ↓
2. GenerateSupportReportJob（バックグラウンド）
   ↓
3. SupportReportGeneratorService
   ↓
4. 対象期間の日報データを取得
   ↓
5. テンプレートとプロンプトを構築
   ↓
6. OpenAI Chat API（gpt-4o）で生成
   ↓
7. 支援報告書のcontentカラムに保存
   ↓
8. ステータスを「完成」に更新
```

---

## 🐛 修正された問題

### Before（問題）

1. **OpenAI API Key未設定時**
   - エラーメッセージが不明瞭
   - "Unauthorized"などの一般的なエラー
   - 原因の特定が困難

2. **ImageMagick不在時**
   - ジョブが失敗するが原因不明
   - ログに詳細情報なし

3. **AWS S3未設定時**
   - ファイルがlocalに保存される
   - Dyno再起動で消失
   - エラーなく動作するため気づきにくい

4. **Worker未起動時**
   - ジョブが実行されない
   - タイムアウト or 永久待機
   - 原因の診断方法がわからない

### After（修正後）

1. **OpenAI API Key未設定時**
   - ✅ 明確なエラーメッセージ
   - ✅ 設定方法の具体的な指示
   - ✅ 初期化時点でチェック

2. **ImageMagick不在時**
   - ✅ 詳細なエラーメッセージ
   - ✅ Heroku Buildpackの追加コマンド表示
   - ✅ ジョブ実行前にチェック

3. **AWS S3未設定時**
   - ✅ 警告メッセージ
   - ✅ 本番環境での推奨設定を表示
   - ✅ 診断タスクで検出

4. **Worker未起動時**
   - ✅ 診断タスクで確認可能
   - ✅ スケールコマンドの提示
   - ✅ プロセス状態の確認方法

---

## ✅ テスト方法

### ローカル環境での診断

```bash
# 診断を実行
bin/rails support_reports:check_config

# テスト生成（開発環境のみ）
bin/rails support_reports:test_generate
```

### Heroku本番環境での診断

```bash
# 環境変数を確認
heroku config --app your-app-name | grep -E "OPENAI|AWS|RAILS_MASTER"

# Buildpackを確認
heroku buildpacks --app your-app-name

# プロセスを確認
heroku ps --app your-app-name

# 診断を実行
heroku run bin/rails support_reports:check_config --app your-app-name

# ログを監視
heroku logs --tail --app your-app-name
```

---

## 📖 関連ドキュメント

| ドキュメント | 用途 |
|------------|------|
| `SUPPORT_REPORTS_QUICKSTART.md` | 最短5ステップでの設定（初心者向け） |
| `HEROKU_SUPPORT_REPORTS_SETUP.md` | 詳細な設定手順とトラブルシューティング |
| `lib/tasks/check_support_reports.rake` | 診断タスクのソースコード |

---

## 🚀 デプロイ手順

```bash
# 1. コードをコミット
git add .
git commit -m "Add support reports production diagnostics and setup guides"

# 2. Herokuにプッシュ
git push heroku main

# 3. 環境変数を設定（上記の必須環境変数を参照）

# 4. Buildpackを追加
heroku buildpacks:add https://github.com/DarthSim/heroku-buildpack-imagemagick --app your-app-name

# 5. Workerを起動
heroku ps:scale worker=1 --app your-app-name

# 6. 再起動
heroku restart --app your-app-name

# 7. 診断を実行
heroku run bin/rails support_reports:check_config --app your-app-name
```

---

## 💡 今後の改善案

1. **自動診断機能**
   - アプリ起動時に自動で設定チェック
   - 管理画面に診断結果を表示

2. **管理画面での設定確認**
   - UIから環境変数の設定状態を確認
   - ステータスインジケーター

3. **リトライ機能**
   - OpenAI API失敗時の自動リトライ
   - 指数バックオフ

4. **通知機能**
   - ジョブ完了時のメール通知
   - LINE通知との連携

---

**以上が支援報告書機能の本番環境対応の変更内容です。**
