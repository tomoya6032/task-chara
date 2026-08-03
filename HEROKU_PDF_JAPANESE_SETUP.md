# Heroku本番環境 日本語PDF出力対応ガイド

## 📋 概要

Heroku本番環境で支援報告書（AI生成テキスト含む）を日本語PDFとして正しく出力するための設定ガイドです。

---

## 🔍 問題の原因

### なぜ本番環境で日本語が文字化けするのか？

1. **Heroku Linuxに日本語フォントがデフォルトでインストールされていない**
   - 開発環境（macOS）: システムに日本語フォントあり → PDF生成成功
   - 本番環境（Heroku/Linux）: 日本語フォントなし → 文字化けまたは空白

2. **wkhtmltopdfがフォントファイルを見つけられない**
   - `font-family: 'Noto Sans JP'`と指定しても、`@font-face`でファイルの場所を明示しないとwkhtmltopdfは認識しない

---

## ✅ 実装した修正内容

### 1. PDFテンプレートに`@font-face`を追加

**ファイル:** `app/views/support_reports/pdf_template.html.haml`

```haml
:css
  /* 日本語フォントの明示的な定義 */
  @font-face {
    font-family: 'Noto Sans CJK JP';
    src: url('file://#{Rails.root}/app/assets/fonts/NotoSansCJKjp-Regular.otf') format('opentype');
    font-weight: normal;
    font-style: normal;
  }
  @font-face {
    font-family: 'IPAexGothic';
    src: url('file://#{Rails.root}/app/assets/fonts/ipaexg.ttf') format('truetype');
    font-weight: normal;
    font-style: normal;
  }
  body {
    font-family: 'Noto Sans CJK JP', 'IPAexGothic', 'MS Gothic', sans-serif;
    /* ... */
  }
```

**変更点:**
- ✅ `@font-face`で`app/assets/fonts`のフォントファイルを直接指定
- ✅ `file://`プロトコルでローカルファイルアクセス
- ✅ フォールバック設定（Noto Sans CJK JP → IPAexGothic → MS Gothic）

---

### 2. Aptfileに日本語フォントパッケージを追加

**ファイル:** `Aptfile`

```
imagemagick
fonts-noto-cjk
fonts-ipafont-gothic
fontconfig
```

**追加パッケージ:**
- `fonts-noto-cjk`: Noto Sans CJK（中国語・日本語・韓国語）フォント
- `fonts-ipafont-gothic`: IPAフォント（日本語）
- `fontconfig`: フォント設定管理ツール

---

### 3. PDF生成サービスの最適化

**ファイル:** `app/services/support_report_pdf_generator.rb`

```ruby
WickedPdf.new.pdf_from_string(
  html,
  page_size: "A4",
  margin: { top: 20, bottom: 20, left: 20, right: 20 },
  encoding: "UTF-8",
  enable_local_file_access: true,
  zoom: 1.0,
  dpi: 96,
  # 日本語フォント対応の追加オプション
  print_media_type: true,
  disable_smart_shrinking: false,
  log_level: "error"
)
```

**追加オプション:**
- `print_media_type: true`: CSSのprintメディアタイプを適用
- `disable_smart_shrinking: false`: コンテンツの自動縮小を有効化
- `log_level: "error"`: エラーログの出力レベル設定

---

## 🚀 Herokuデプロイ手順

### ステップ1: Buildpack設定

heroku-community/aptビルドパックが既に設定されている場合はスキップ。

```bash
# apt buildpackを追加（Aptfileを読み込むため）
heroku buildpacks:add --index 1 heroku-community/apt --app task-chara-tomoya

# 設定を確認
heroku buildpacks --app task-chara-tomoya
```

**期待される出力:**
```
=== task-chara-tomoya Buildpack URLs
1. heroku-community/apt
2. heroku/ruby
```

---

### ステップ2: 変更をコミット

```bash
# 変更されたファイルを確認
git status

# ステージング
git add Aptfile \
  app/views/support_reports/pdf_template.html.haml \
  app/services/support_report_pdf_generator.rb

# コミット
git commit -m "Heroku本番環境で日本語PDF出力対応

- PDFテンプレートに@font-faceでフォントファイルを明示的に指定
- Aptfileに日本語フォントパッケージを追加 (fonts-noto-cjk, fonts-ipafont-gothic)
- PDF生成サービスにprint_media_type等のオプションを追加"
```

---

### ステップ3: Herokuにデプロイ

```bash
# developmentブランチからmainにデプロイ
git push heroku development:main

# または、mainブランチから
git push heroku main
```

**デプロイログで確認すべきポイント:**

```
-----> Apt app detected
-----> Updating apt caches
-----> Installing fonts-noto-cjk fonts-ipafont-gothic fontconfig
       ...
-----> Ruby app detected
       ...
```

✅ 上記のように`fonts-noto-cjk`等がインストールされていることを確認

---

### ステップ4: デプロイ後の動作確認

```bash
# ログをリアルタイム監視
heroku logs --tail --app task-chara-tomoya

# Herokuのコンソールでフォント確認（オプション）
heroku run bash --app task-chara-tomoya
fc-list | grep -i "noto\|ipa"
exit
```

---

## 🧪 動作テスト手順

### 1. 本番環境で支援報告書を作成

1. Heroku本番アプリにアクセス
2. 日報データから支援報告書を生成（AI生成機能を使用）
3. プレビュー画面で日本語が正しく表示されることを確認

### 2. PDFダウンロードをテスト

1. 「PDF出力」ボタンをクリック
2. ダウンロードされたPDFを開く
3. **確認項目:**
   - ✅ 日本語が正しく表示されている
   - ✅ AI生成テキストの改行・整形が保たれている
   - ✅ 太字・下線・ハイライト等の装飾が適用されている
   - ✅ 文字化けや空白がない

---

## 🔧 トラブルシューティング

### ❌ PDF生成時に500エラーが発生する

**原因:** wkhtmltopdfのバイナリが見つからない、または実行権限がない

**解決策:**
```bash
# wkhtmltopdf-binaryがインストールされているか確認
heroku run "bundle exec ruby -e \"require 'wkhtmltopdf-binary'; puts WkhtmltopdfBinary.path\"" --app task-chara-tomoya

# パスが表示されればOK
# エラーが出た場合はGemfileにwkhtmltopdf-binaryがあるか確認
```

---

### ❌ 日本語は表示されるがレイアウトが崩れる

**原因:** フォントファイルのサイズが大きく、レンダリングに時間がかかっている

**解決策1:** `wicked_pdf.rb`でタイムアウトを延長

```ruby
# config/initializers/wicked_pdf.rb
WickedPdf.configure do |c|
  c.enable_local_file_access = true
  # タイムアウトを60秒に延長
  c.command_line_options = { timeout: 60 }
end
```

**解決策2:** PDFテンプレートでzoomを調整

```css
body {
  zoom: 1.0; /* 1.25から1.0に変更してサイズを小さく */
}
```

---

### ❌ 一部の漢字だけ文字化けする

**原因:** Noto Sans CJK JPに含まれていない漢字（異体字・旧字体等）

**解決策:** IPAexフォントをフォールバックに追加（既に実装済み）

```css
body {
  font-family: 'Noto Sans CJK JP', 'IPAexGothic', 'MS Gothic', sans-serif;
}
```

---

### ❌ Aptfileのパッケージインストールに失敗する

**エラー例:**
```
E: Unable to locate package fonts-noto-cjk
```

**解決策:** Heroku Stackを確認

```bash
# 現在のStackを確認
heroku stack --app task-chara-tomoya

# heroku-22以降が必要
# heroku-20の場合はアップグレード
heroku stack:set heroku-22 --app task-chara-tomoya
```

---

## 📊 技術仕様

### 使用ライブラリ

| Gem | バージョン | 用途 |
|-----|-----------|------|
| wicked_pdf | - | HTML→PDF変換ラッパー |
| wkhtmltopdf-binary | - | PDF生成エンジン |
| mini_magick | ~> 4.11 | 画像処理（PDFテンプレート解析用） |

### フォントファイル

| ファイル | 場所 | サイズ | 用途 |
|---------|------|--------|------|
| NotoSansCJKjp-Regular.otf | app/assets/fonts/ | ~23MB | メインの日本語フォント |
| ipaexg.ttf | app/assets/fonts/ | ~4MB | フォールバック用 |

### Aptパッケージ

| パッケージ | 用途 |
|-----------|------|
| fonts-noto-cjk | Noto Sans CJKフォント（システムレベル） |
| fonts-ipafont-gothic | IPAフォント（システムレベル） |
| fontconfig | フォント設定管理 |
| imagemagick | PDF構造解析用 |

---

## 💰 コスト影響

### Herokuリソース使用量

- **Slugサイズ増加:** 約30MB（フォントパッケージ）
- **ビルド時間増加:** 約30秒～1分
- **PDF生成時メモリ:** 約100～200MB（1回あたり）

**推奨Dyno:**
- 通常の使用: Standard-1X以上
- 大量PDF生成: Standard-2X以上

---

## 📝 チェックリスト

デプロイ前の確認事項:

- [ ] `Aptfile`に日本語フォントパッケージを追加
- [ ] `pdf_template.html.haml`に`@font-face`を追加
- [ ] `support_report_pdf_generator.rb`にオプションを追加
- [ ] heroku-community/aptビルドパックを設定
- [ ] 変更をgit commit
- [ ] Heroku環境変数（OPENAI_API_KEY、RAILS_MASTER_KEY）を設定済み

デプロイ後の確認事項:

- [ ] デプロイログで`fonts-noto-cjk`のインストールを確認
- [ ] 本番環境でPDF生成テスト実行
- [ ] 日本語が正しく表示されることを確認
- [ ] AI生成テキストの装飾（太字・下線等）が反映されることを確認

---

## 🆘 サポート

問題が解決しない場合:

1. **Herokuログを確認:**
   ```bash
   heroku logs --tail --app task-chara-tomoya
   ```

2. **PDF生成の詳細ログを有効化:**
   ```ruby
   # app/services/support_report_pdf_generator.rb
   log_level: "warn"  # "error"から"warn"に変更
   ```

3. **wkhtmltopdfのバージョン確認:**
   ```bash
   heroku run "wkhtmltopdf --version" --app task-chara-tomoya
   ```

---

## 📚 参考リンク

- [wicked_pdf GitHub](https://github.com/mileszs/wicked_pdf)
- [wkhtmltopdf Documentation](https://wkhtmltopdf.org/)
- [Heroku Apt Buildpack](https://github.com/heroku/heroku-buildpack-apt)
- [Noto Sans CJK](https://github.com/notofonts/noto-cjk)

---

**作成日:** 2026-08-03  
**対象環境:** Heroku / Rails 8.0.4 / Ruby 3.3.12
