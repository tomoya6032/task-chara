# 支援報告書機能 - Heroku本番環境 クイックスタート

開発環境で動作している支援報告書機能を本番環境（Heroku）で動作させるための最小限の手順です。

## 🚀 最短5ステップで設定完了

### 前提条件
- Heroku CLIがインストールされている
- Herokuアプリが作成済み
- OpenAI APIキーを取得済み
- AWS S3バケットを作成済み（推奨）

---

## ステップ1: 診断実行（現状確認）

まず、ローカル開発環境で診断タスクを実行し、現在の設定を確認します。

```bash
bin/rails support_reports:check_config
```

**期待される出力:**
```
🔍 支援報告書機能 - 設定診断
============================
1. OpenAI API Key... ✅ 設定済み
2. Active Storage... local
3. ImageMagick... ✅ インストール済み
...
```

---

## ステップ2: 環境変数の設定（必須）

### A. OpenAI API Key（必須）

```bash
heroku config:set OPENAI_API_KEY=sk-proj-XXXXXXXXXXXX --app your-app-name
```

**APIキーの取得:**
1. https://platform.openai.com/api-keys にアクセス
2. "Create new secret key" をクリック
3. キーをコピーして保存（再表示されません）

---

### B. AWS S3認証情報（推奨 - ファイル保存に必須）

```bash
heroku config:set \
  AWS_ACCESS_KEY_ID=AKIAXXXXXXXXXXXXXXXX \
  AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  AWS_S3_BUCKET=your-bucket-name \
  AWS_REGION=ap-northeast-1 \
  --app your-app-name
```

**S3バケットの準備:**
```
1. AWSコンソール → S3 → バケットを作成
2. バケット名: 例 taskcharacter-production（一意な名前）
3. リージョン: ap-northeast-1（東京）
4. パブリックアクセス: すべてブロック（デフォルト）
5. IAMユーザーを作成してアクセスキーを取得
   - ポリシー: AmazonS3FullAccess または最小権限ポリシー
```

---

### C. RAILS_MASTER_KEY（credentials使用時）

```bash
# ローカルのmaster.keyをコピー
cat config/master.key
# → 出力された32文字の文字列をコピー

# Herokuに設定
heroku config:set RAILS_MASTER_KEY=xxxxxxxxxxxxxxxxxxxxx --app your-app-name
```

---

## ステップ3: Buildpackの追加（PDF処理に必須）

```bash
# ImageMagick Buildpackを追加
heroku buildpacks:add --index 1 https://github.com/DarthSim/heroku-buildpack-imagemagick --app your-app-name

# 確認
heroku buildpacks --app your-app-name
```

**期待される出力:**
```
1. https://github.com/DarthSim/heroku-buildpack-imagemagick
2. heroku/ruby
```

---

## ステップ4: Workerプロセスの起動（バックグラウンドジョブ実行に必須）

```bash
# Workerを1台起動
heroku ps:scale worker=1 --app your-app-name

# 確認
heroku ps --app your-app-name
```

**期待される出力:**
```
=== web (Standard-1X): bundle exec puma -C config/puma.rb
web.1: up 2024/01/01 10:00:00 (~ 1h ago)

=== worker (Standard-1X): bundle exec rake solid_queue:start
worker.1: up 2024/01/01 10:00:00 (~ 1h ago)
```

⚠️ **注意:** Workerプロセスは追加料金が発生します（Standard-1X: 約$25/月）

---

## ステップ5: 再デプロイと動作確認

```bash
# Buildpack変更を反映するため再デプロイ
git commit --allow-empty -m "Enable support reports feature"
git push heroku main

# または、再起動のみ
heroku restart --app your-app-name
```

### 本番環境で診断を実行

```bash
# Heroku上で診断タスクを実行
heroku run bin/rails support_reports:check_config --app your-app-name
```

**期待される出力:**
```
✅ すべての設定が正常です！
支援報告書機能は正しく動作する準備が整っています。
```

---

## 🧪 動作テスト

### 1. テンプレート作成のテスト

```
1. https://your-app-name.herokuapp.com にログイン
2. 支援報告書 → テンプレート管理 → 新規作成
3. PDFファイルをアップロード
4. 保存
5. 数秒〜数十秒後、テンプレートの内容が自動抽出される
```

### 2. AI生成のテスト

```
1. 日報データを3件以上作成
2. 支援報告書 → 新規作成
3. 対象期間とテンプレートを選択
4. 「生成」ボタンをクリック
5. ステータスが「生成中」→「完成」に変わる
6. 生成された報告書を確認
```

---

## ⚠️ トラブルシューティング

### エラー: "OpenAI API Keyが設定されていません"

```bash
heroku config:get OPENAI_API_KEY --app your-app-name
# → 値が表示されない場合は未設定

heroku config:set OPENAI_API_KEY=your_key --app your-app-name
```

---

### エラー: "ファイルが保存されませんでした"

```bash
# S3設定を確認
heroku config:get AWS_ACCESS_KEY_ID --app your-app-name
heroku config:get AWS_SECRET_ACCESS_KEY --app your-app-name
heroku config:get AWS_S3_BUCKET --app your-app-name

# すべて設定されていることを確認
# 未設定の場合はステップ2-Bを実行
```

---

### エラー: "ImageMagickがインストールされていません"

```bash
# Buildpackを確認
heroku buildpacks --app your-app-name

# ImageMagick buildpackがない場合は追加
heroku buildpacks:add https://github.com/DarthSim/heroku-buildpack-imagemagick --app your-app-name

# 再デプロイ（必須）
git commit --allow-empty -m "Add ImageMagick buildpack"
git push heroku main
```

---

### ジョブが実行されない

```bash
# Workerプロセスを確認
heroku ps --app your-app-name

# Workerが起動していない場合
heroku ps:scale worker=1 --app your-app-name
```

---

## 📋 設定確認チェックリスト

コピーして使用してください：

```bash
# 1. 環境変数の確認
heroku config --app your-app-name | grep -E "OPENAI|AWS|RAILS_MASTER"

# 2. Buildpackの確認
heroku buildpacks --app your-app-name

# 3. プロセスの確認
heroku ps --app your-app-name

# 4. 診断の実行
heroku run bin/rails support_reports:check_config --app your-app-name

# 5. ログの監視
heroku logs --tail --app your-app-name
```

---

## ✅ 完了チェックリスト

- [ ] `OPENAI_API_KEY` を設定した
- [ ] AWS S3の認証情報を設定した（AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_S3_BUCKET）
- [ ] `RAILS_MASTER_KEY` を設定した
- [ ] ImageMagick Buildpackを追加した
- [ ] Workerプロセスを1台起動した
- [ ] 再デプロイを実行した
- [ ] 診断タスクで「✅ すべての設定が正常です」と表示された
- [ ] テンプレート作成とPDF解析が動作した
- [ ] AI生成が動作した

---

## 📚 詳細ドキュメント

より詳しい情報、トラブルシューティング、コスト見積もりについては、以下のドキュメントを参照してください：

- **[HEROKU_SUPPORT_REPORTS_SETUP.md](HEROKU_SUPPORT_REPORTS_SETUP.md)** - 詳細な設定手順とトラブルシューティング

---

## 💡 ヒント

### コストを抑えるには

1. **Workerプロセスのスケールダウン**
   ```bash
   # 使用しない時間帯はWorkerを停止
   heroku ps:scale worker=0 --app your-app-name
   
   # 使用時のみ起動
   heroku ps:scale worker=1 --app your-app-name
   ```

2. **S3のライフサイクルポリシー**
   - 古いPDFファイルを自動削除（例: 90日後）
   - Glacier（低コストストレージ）への自動移行

3. **OpenAI APIの使用量管理**
   - OpenAIダッシュボードで使用量制限を設定
   - https://platform.openai.com/account/billing/limits

---

## 🆘 サポート

問題が解決しない場合:

1. ログを確認: `heroku logs --tail --app your-app-name`
2. 診断を実行: `heroku run bin/rails support_reports:check_config --app your-app-name`
3. 詳細ドキュメントを確認: `HEROKU_SUPPORT_REPORTS_SETUP.md`
4. エラーメッセージをコピーして検索

---

**設定完了後は本番環境で実際にテストして動作を確認してください！**
