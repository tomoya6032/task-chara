# LINE連携の環境変数設定ガイド

このガイドに従って、LINE連携に必要な環境変数を設定してください。

---

## ステップ1: LINE Developers Consoleでチャネルを設定

### 1-1. LINE Login Channelを作成（新規）

1. **LINE Developers Consoleにアクセス**
   - URL: https://developers.line.biz/console/
   - LINEアカウントでログイン

2. **プロバイダーを選択**
   - 既存のプロバイダーを選択、または新規作成

3. **LINE Login Channelを作成**
   - 「新しいチャネルを作成」ボタンをクリック
   - **「LINE Login」を選択**
   - 以下を入力：
     - チャネル名: `TaskChara Login`
     - チャネル説明: `TaskCharaのLINE連携用`
     - アプリタイプ: **ウェブアプリ**
   - 利用規約に同意して「作成」

4. **Callback URLを設定**
   - 作成したチャネルの「チャネル基本設定」タブを開く
   - 「Callback URL」欄に以下を入力：
     ```
     http://localhost:3000/line_login/callback
     ```
   - 「更新」ボタンをクリック

5. **認証情報を取得**
   - 同じ「チャネル基本設定」ページで以下をコピー：
     - **Channel ID**: 10桁程度の数字（例: 1234567890）
     - **Channel secret**: 32文字の英数字（例: abcd1234efgh5678ijkl...）

### 1-2. Messaging API Channelを確認（既存）

既にMessaging API Channelが作成されているはずです。

1. **Messaging API Channelを開く**
   - LINE Developers Console → 該当のMessaging API Channel

2. **Channel Secretを取得**
   - 「チャネル基本設定」タブ
   - **Channel secret**をコピー（32文字の英数字）

3. **Channel Access Tokenを取得**
   - 「Messaging API設定」タブ
   - 「Channel access token (long-lived)」セクション
   - 既に発行されていればそれをコピー
   - なければ「発行」ボタンをクリックしてコピー

4. **Webhook URLを確認**
   - 「Messaging API設定」タブ
   - Webhook URLに以下が設定されているか確認：
     ```
     http://localhost:3000/line/callback
     ```
   - Webhookの利用が「オン」になっているか確認

5. **友だち追加URLを取得**
   - 「Messaging API設定」タブ
   - QRコードセクションの友だち追加リンクをコピー
   - 形式: `https://line.me/R/ti/p/@xxxxx`

6. **QRコードをダウンロード（オプション）**
   - 同じQRコードセクションで「ダウンロード」ボタンをクリック
   - ダウンロードした画像を `app/assets/images/LINE QR.png` として保存

---

## ステップ2: .envファイルに環境変数を設定

プロジェクトルートの `.env` ファイルを開いて、以下を追加してください。

```bash
# ===================================================================
# LINE連携設定
# ===================================================================

# ----- LINE Login（OAuth認証用）-----
# LINE Developers Console → LINE Login Channel → チャネル基本設定
LINE_LOGIN_CHANNEL_ID=ここにChannel_IDを貼り付け
LINE_LOGIN_CHANNEL_SECRET=ここにChannel_Secretを貼り付け

# ----- LINE Messaging API（メッセージ送信用）-----
# LINE Developers Console → Messaging API Channel
LINE_CHANNEL_SECRET=ここにMessaging_API_Channel_Secretを貼り付け
LINE_CHANNEL_ACCESS_TOKEN=ここにChannel_Access_Tokenを貼り付け

# ----- 友だち追加URL -----
# Messaging API Channel → Messaging API設定 → QRコード
LINE_ADD_FRIEND_URL=https://line.me/R/ti/p/@xxxxx

# ----- QRコード画像（オプション）-----
# デフォルト: LINE QR.png
# LINE_QR_CODE_IMAGE=LINE QR.png
```

### 設定例（実際の値に置き換えてください）

```bash
# 例（実際の値を使ってください）
LINE_LOGIN_CHANNEL_ID=1234567890
LINE_LOGIN_CHANNEL_SECRET=abcd1234efgh5678ijkl9012mnop3456
LINE_CHANNEL_SECRET=1234abcd5678efgh9012ijkl3456mnop
LINE_CHANNEL_ACCESS_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...（長い文字列）
LINE_ADD_FRIEND_URL=https://line.me/R/ti/p/@abc1234
```

---

## ステップ3: Railsサーバーを再起動

環境変数を追加したら、必ずRailsサーバーを再起動してください。

```bash
# ターミナルで Ctrl+C を押してサーバーを停止
# その後、再起動
bin/dev
```

または

```bash
rails server
```

---

## ステップ4: 動作確認

### 4-1. 設定画面を開く
1. ブラウザで http://localhost:3000/settings を開く
2. 「📱 LINE通知連携（リマインド用）」セクションを確認

### 4-2. エラーがないか確認
- 「※管理者がQRコード画像またはLINE_ADD_FRIEND_URLを設定してください」と表示される場合
  → `LINE_ADD_FRIEND_URL` が設定されていません
  
- 「LINEと連携する」ボタンを押して「LINE連携の設定が完了していません」と表示される場合
  → `LINE_LOGIN_CHANNEL_ID` または `LINE_LOGIN_CHANNEL_SECRET` が設定されていません

### 4-3. 連携テスト
1. スマホで公式LINEアカウントを友だち追加
2. 設定ページで「LINEと連携する」ボタンをクリック
3. LINEのログイン画面が表示されたらログイン
4. 「同意して連携する」をタップ
5. 設定ページに戻り「連携済み（通知オン）」と表示されれば成功！

---

## トラブルシューティング

### Q1: 「LINE連携の設定が完了していません」エラー
**原因**: `LINE_LOGIN_CHANNEL_ID` が設定されていない  
**解決**: `.env` ファイルに `LINE_LOGIN_CHANNEL_ID` を追加してサーバー再起動

### Q2: 「不正なリクエスト」エラー
**原因**: Callback URLが正しく設定されていない  
**解決**: LINE Developers Console → LINE Login Channel → Callback URLを確認

### Q3: QRコードが表示されない
**原因**: 画像ファイルが配置されていない、またはURLが未設定  
**解決**: 
- `app/assets/images/LINE QR.png` に画像を配置
- または `LINE_ADD_FRIEND_URL` を設定

### Q4: 「このLINEアカウントは既に別のユーザーと連携されています」
**原因**: 1つのLINEアカウントは1つのユーザーアカウントとしか連携できない  
**解決**: 既存の連携を解除してから再連携

### Q5: リマインド通知が届かない
**確認事項**:
1. 公式LINEアカウントを友だち追加しているか
2. 設定ページで「連携済み」になっているか
3. LINE公式アカウントをブロックしていないか
4. カレンダーにイベントが登録されているか（15分前に通知）

---

## 本番環境へのデプロイ

本番環境では、Callback URLを本番のドメインに変更してください。

### LINE Developers Consoleで設定
1. LINE Login Channel → Callback URL
   ```
   https://yourdomain.com/line_login/callback
   ```

2. Messaging API Channel → Webhook URL
   ```
   https://yourdomain.com/line/callback
   ```

### 環境変数
Herokuの場合：
```bash
heroku config:set LINE_LOGIN_CHANNEL_ID=your_id
heroku config:set LINE_LOGIN_CHANNEL_SECRET=your_secret
heroku config:set LINE_CHANNEL_SECRET=your_secret
heroku config:set LINE_CHANNEL_ACCESS_TOKEN=your_token
heroku config:set LINE_ADD_FRIEND_URL=your_url
```

---

## まとめ

必要な環境変数（5つ）:
1. ✅ `LINE_LOGIN_CHANNEL_ID` - LINE Login Channel ID
2. ✅ `LINE_LOGIN_CHANNEL_SECRET` - LINE Login Channel Secret
3. ✅ `LINE_CHANNEL_SECRET` - Messaging API Channel Secret
4. ✅ `LINE_CHANNEL_ACCESS_TOKEN` - Messaging API Access Token
5. ✅ `LINE_ADD_FRIEND_URL` - 友だち追加URL

これらすべてを設定して、サーバーを再起動すれば完了です！
