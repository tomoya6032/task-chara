# LINE連携機能のセットアップ

## 概要
この機能は、ユーザーがLINEでタスク期限やスケジュールのリマインド通知を受け取れるようにするものです。LINE Messaging APIとLINE Login OAuthを使用して、ワンクリックで安全に連携できます。

## 連携の仕組み
1. ユーザーが公式LINEアカウントを友だち追加
2. 設定ページで「LINEと連携する」ボタンをクリック
3. LINE Login OAuth認証で自動的にアカウント連携
4. リマインド通知を受信可能に

**メールアドレスの入力は不要です**。ブラウザでボタンを押すだけで連携完了します。

---

## セットアップ手順

### 必要なLINE Channelは2つです

1. **LINE Login Channel** - ユーザー認証用（OAuth連携）
2. **Messaging API Channel** - メッセージ送信用（既存）

---

## LINE通知連携（リマインド用）の設定

### 前提条件
1. [LINE Developers Console](https://developers.line.biz/console/)でアカウントを作成
2. Messaging API Channelを作成済み
3. LINE Login Channelを作成済み

### 1. LINE Login Channelの作成

1. **LINE Developers Consoleにログイン**
   - https://developers.line.biz/console/ にアクセス

2. **プロバイダーを作成（まだない場合）**
   - 「プロバイダーを作成」をクリック
   - プロバイダー名を入力（例: TaskChara）

3. **LINE Login Channelを作成**
   - 「新しいチャネルを作成」→「LINE Login」を選択
   - 必要情報を入力：
     - チャネル名: TaskChara Login
     - チャネル説明: TaskCharaのLINE連携用
     - アプリタイプ: ウェブアプリ

4. **Callback URLを設定**
   - チャネル基本設定 → Callback URL
   - 開発環境: `http://localhost:3000/line_login/callback`
   - 本番環境: `https://yourdomain.com/line_login/callback`

5. **Channel IDとChannel Secretを取得**
   - チャネル基本設定ページから以下をコピー：
     - Channel ID
     - Channel Secret

### 2. Messaging API Channelの確認

既存のMessaging API Channelを使用します。

1. **Channel Access Tokenを確認**
   - Messaging API設定 → Channel access token (long-lived)
   - 発行されていない場合は「発行」ボタンをクリック

2. **Webhook URLを設定**
   - 開発環境: `http://localhost:3000/line/callback`
   - 本番環境: `https://yourdomain.com/line/callback`
   - Webhookの利用: 有効化

3. **友だち追加URLを取得**
   - Messaging API設定 → QRコード
   - 友だち追加リンクをコピー（`https://line.me/R/ti/p/@xxx` 形式）
   - QRコードをダウンロード（オプション）

### 3. 環境変数の設定

#### 開発環境 (.env ファイル)
```bash
# LINE Login（リマインド連携用）
LINE_LOGIN_CHANNEL_ID=your_login_channel_id
LINE_LOGIN_CHANNEL_SECRET=your_login_channel_secret

# LINE Messaging API
LINE_CHANNEL_SECRET=your_messaging_channel_secret
LINE_CHANNEL_ACCESS_TOKEN=your_messaging_channel_access_token

# 友だち追加URL（必須）
LINE_ADD_FRIEND_URL=https://line.me/R/ti/p/@your_bot_id

# QRコード画像パス（オプション）
# LINE_QR_CODE_IMAGE=line_friend_qr.png
```

#### QRコード画像の配置（オプション）

設定画面にQRコードを表示したい場合：

1. **QRコード画像をダウンロード**
   - LINE Developers Console → Messaging API設定 → QRコード
   - 「ダウンロード」ボタンでQRコード画像を保存

2. **画像をプロジェクトに配置**
   ```bash
   # 画像を app/assets/images/ に配置
   cp ~/Downloads/line_qr.png app/assets/images/line_friend_qr.png
   ```

3. **環境変数を設定（オプション）**
   - デフォルトでは `line_friend_qr.png` を探します
   - 別のファイル名を使う場合：
     ```bash
     LINE_QR_CODE_IMAGE=your_qr_code.png
     ```

QRコード画像が存在する場合、設定画面に自動的に表示されます。

#### 本番環境
環境に応じて環境変数を設定してください：

- **Heroku**:
  ```bash
  heroku config:set LINE_LOGIN_CHANNEL_ID=your_id
  heroku config:set LINE_LOGIN_CHANNEL_SECRET=your_secret
  heroku config:set LINE_CHANNEL_SECRET=your_secret
  heroku config:set LINE_CHANNEL_ACCESS_TOKEN=your_token
  heroku config:set LINE_ADD_FRIEND_URL=https://line.me/R/ti/p/@xxx
  ```

- **Docker**: `docker-compose.yml`または環境変数ファイルに設定

### 4. Rails Credentialsを使用する場合（推奨）

```bash
# credentialsを編集
EDITOR="code --wait" rails credentials:edit
```

以下を追加：
```yaml
line_login:
  channel_id: your_login_channel_id
  channel_secret: your_login_channel_secret

line:
  channel_secret: your_messaging_channel_secret
  channel_access_token: your_messaging_channel_access_token
```

## ユーザー側の連携手順

1. **設定ページにアクセス**
   - ログイン後、「⚙️ 設定」ページを開く

2. **LINE通知連携セクションで連携**
   - 「📱 LINE通知連携（リマインド用）」セクションを確認
   - ステップ1: 公式LINEアカウントを友だち追加
   - ステップ2: 「LINEと連携する」ボタンをクリック
   - ステップ3: LINE認証画面で「同意」する

3. **連携完了**
   - 自動的に設定ページに戻り、「連携済み（通知オン）」と表示される
   - これでリマインド通知を受け取れるようになります

## トラブルシューティング

### 「LINE連携の設定が完了していません」と表示される
- 環境変数 `LINE_LOGIN_CHANNEL_ID` が設定されているか確認
- または Rails credentials に `line_login.channel_id` が設定されているか確認

### 「不正なリクエスト」エラー
- Callback URLが正しく設定されているか確認
- LINE Developers Console のCallback URLとアプリのURLが一致しているか確認

### 「このLINEアカウントは既に別のユーザーと連携されています」
- 1つのLINEアカウントは1つのユーザーアカウントとしか連携できません
- 既存の連携を解除してから再度連携してください

### リマインド通知が届かない
1. LINE公式アカウントを友だち追加しているか確認
2. 設定ページで「連携済み」になっているか確認
3. LINE公式アカウントをブロックしていないか確認
4. サーバーログで送信エラーが出ていないか確認

## 開発者向け情報

### LINE Login OAuth フロー

1. **認可リクエスト** (`/line_login/authorize`)
   - `https://access.line.me/oauth2/v2.1/authorize` にリダイレクト
   - パラメータ: `response_type=code`, `client_id`, `redirect_uri`, `state`, `scope=profile`

2. **コールバック** (`/line_login/callback`)
   - 認可コード (`code`) を受け取る
   - `https://api.line.me/oauth2/v2.1/token` でアクセストークンと交換
   - `https://api.line.me/v2/profile` でユーザー情報取得
   - `userId` を `users.line_user_id` に保存

3. **連携解除** (`DELETE /settings/line`)
   - `users.line_user_id` を `nil` に更新

### リマインド送信の仕組み

1. **定期ジョブ** (`CheckEventRemindersJob`)
   - 15分後に開始するイベントを検索
   - イベントのユーザーに `line_user_id` があるか確認

2. **LINE送信** (`SendLineReminderJob`)
   - `LineMessagingService` を使用
   - Messaging API でプッシュメッセージ送信

### 関連ファイル
- コントローラー: `app/controllers/line_login_controller.rb`
- ビュー: `app/views/settings/show.html.haml`
- ルーティング: `config/routes.rb`
- ジョブ: `app/jobs/send_line_reminder_job.rb`
- サービス: `app/services/line_messaging_service.rb`

