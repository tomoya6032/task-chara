# Heroku PDF出力設定ガイド

## 概要
このアプリケーションでは、WickedPDFを使用してPDFを生成しています。
Heroku環境で日本語PDFを正常に出力するには、以下の設定が必要です。

## 必要な設定

### 1. wkhtmltopdf buildpackの追加

Herokuにwkhtmltopdfをインストールするため、buildpackを追加します。

```bash
# wkhtmltopdf buildpackを追加（Ruby buildpackの前に追加すること）
heroku buildpacks:add --index 1 https://github.com/dscout/wkhtmltopdf-buildpack.git -a task-chara-tomoya-352cae49d006

# buildpackの確認
heroku buildpacks -a task-chara-tomoya-352cae49d006
```

出力例:
```
=== task-chara-tomoya-352cae49d006 Buildpack URLs
1. https://github.com/dscout/wkhtmltopdf-buildpack.git
2. heroku/ruby
```

### 2. デプロイ

buildpackを追加したら、再デプロイします。

```bash
git push heroku main
```

### 3. 動作確認

- PDF出力機能が正常に動作することを確認
- 日本語が文字化けせずに表示されることを確認

URL: https://task-chara-tomoya-352cae49d006.herokuapp.com/meeting_minutes/4/download_pdf

## トラブルシューティング

### PDF生成に失敗する場合

```bash
# ログを確認
heroku logs --tail -a task-chara-tomoya-352cae49d006

# wkhtmltopdfのパスを確認
heroku run "which wkhtmltopdf" -a task-chara-tomoya-352cae49d006
# 期待される出力: /app/bin/wkhtmltopdf

# wkhtmltopdfのバージョンを確認
heroku run "wkhtmltopdf --version" -a task-chara-tomoya-352cae49d006
```

### 日本語フォントの問題

現在の設定では、Google Fonts (Noto Sans JP) を使用しています。
これにより、フォントファイルをアプリケーションに含める必要がなくなります。

### buildpackが正しく追加されているか確認

```bash
heroku buildpacks -a task-chara-tomoya-352cae49d006
```

wkhtmltopdf buildpackがRuby buildpackより前に表示されていることを確認してください。

## 参考リンク

- [wkhtmltopdf-buildpack](https://github.com/dscout/wkhtmltopdf-buildpack)
- [WickedPDF GitHub](https://github.com/mileszs/wicked_pdf)
- [Google Fonts - Noto Sans JP](https://fonts.google.com/noto/specimen/Noto+Sans+JP)

## コード変更内容

### 1. PDF テンプレート (`app/views/meeting_minutes/pdf_template.html.haml`)
- Google Fonts (Noto Sans JP) を使用
- 外部フォントリソースの読み込み

### 2. WickedPDF 設定 (`config/initializers/wicked_pdf.rb`)
- Heroku環境を検出してwkhtmltopdfパスを自動設定
- `ENV['DYNO']` が存在する場合、`/app/bin/wkhtmltopdf` を使用

### 3. PDF生成サービス (`app/services/meeting_minute_pdf_generator.rb`)
- 外部リンク（Google Fonts）へのアクセスを許可
- `enable_external_links: true` を追加
