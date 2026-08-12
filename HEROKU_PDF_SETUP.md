# Heroku PDF出力設定ガイド

## 概要
このアプリケーションでは、WickedPDFと`wkhtmltopdf-binary` gemを使用してPDFを生成しています。
Heroku環境で日本語PDFを正常に出力するには、以下の設定が必要です。

## 必要な設定

### 1. Gemのインストール

`wkhtmltopdf-binary` gemはすでにGemfileに含まれています。

```ruby
# Gemfile
gem "wkhtmltopdf-binary"
```

デプロイ時に自動的にインストールされます。

### 2. デプロイ

コードをHerokuにデプロイします。

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

# wkhtmltopdfのパスを確認（Railsコンソール内で）
heroku run rails console -a task-chara-tomoya-352cae49d006
# コンソール内で実行:
# Gem.bin_path('wkhtmltopdf-binary', 'wkhtmltopdf')
# 期待される出力: /app/vendor/bundle/ruby/3.x.x/gems/wkhtmltopdf-binary-x.x.x.x/bin/wkhtmltopdf

# wkhtmltopdfのバージョンを確認
heroku run "bundle exec wkhtmltopdf --version" -a task-chara-tomoya-352cae49d006
```

### 日本語フォントの問題

現在の設定では、Google Fonts (Noto Sans JP) を使用しています。
これにより、フォントファイルをアプリケーションに含める必要がなくなります。

### Gemが正しくインストールされているか確認

```bash
heroku run "bundle list | grep wkhtmltopdf" -a task-chara-tomoya-352cae49d006
```

出力例:
```
  * wkhtmltopdf-binary (0.12.6.10)
```

## 参考リンク

- [wkhtmltopdf-binary GitHub](https://github.com/pallymore/wkhtmltopdf-binary-edge)
- [WickedPDF GitHub](https://github.com/mileszs/wicked_pdf)
- [Google Fonts - Noto Sans JP](https://fonts.google.com/noto/specimen/Noto+Sans+JP)

## コード変更内容

### 1. PDF テンプレート (`app/views/meeting_minutes/pdf_template.html.haml`)
- Google Fonts (Noto Sans JP) を使用
- 外部フォントリソースの読み込み

### 2. WickedPDF 設定 (`config/initializers/wicked_pdf.rb`)
- `wkhtmltopdf-binary` gem内の実行ファイルを参照
- `c.exe_path = Gem.bin_path('wkhtmltopdf-binary', 'wkhtmltopdf')`

### 3. PDF生成サービス (`app/services/meeting_minute_pdf_generator.rb`)
- 外部リンク（Google Fonts）へのアクセスを許可
- `enable_external_links: true` を追加

## 注意事項

- **Buildpackは不要**: `wkhtmltopdf-binary` gemを使用するため、Heroku buildpackの追加は不要です
- **クロスプラットフォーム対応**: gemはLinux、macOS、Windowsに対応したバイナリを含んでいます
- **デプロイのみで動作**: コードをプッシュするだけで、Heroku環境でwkhtmltopdfが自動的に利用可能になります
