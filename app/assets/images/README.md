# 画像アセット

## LINE友だち追加QRコード

LINE通知連携機能の設定画面にQRコードを表示する場合、このディレクトリにQRコード画像を配置してください。

### 配置手順

1. **LINE Developers Consoleからダウンロード**
   - https://developers.line.biz/console/ にアクセス
   - Messaging API Channel → Messaging API設定
   - QRコードセクションで「ダウンロード」をクリック

2. **画像をこのディレクトリに配置**
   ```bash
   # デフォルトのファイル名
   cp ~/Downloads/line_qr.png line_friend_qr.png
   ```

3. **カスタムファイル名を使用する場合**
   環境変数で指定：
   ```bash
   LINE_QR_CODE_IMAGE=your_custom_qr.png
   ```

### 画像要件

- **ファイル名**: `line_friend_qr.png`（デフォルト）
- **形式**: PNG, JPG, GIF（推奨：PNG）
- **推奨サイズ**: 300x300px 以上
- **表示サイズ**: 192x192px（設定画面で自動調整）

### 注意事項

- QRコードが存在しない場合は、友だち追加URLのリンクボタンのみ表示されます
- 本番環境へのデプロイ時は、この画像もコミットしてください
- セキュリティ上、QRコード自体は公開情報なので問題ありません
