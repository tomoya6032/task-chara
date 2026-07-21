# ローディングオーバーレイ実装ガイド

## 📋 概要

ページ遷移やフォーム送信時に、画面全体を覆うローディングオーバーレイを表示し、連打防止とローディング状態の提示を行う機能を実装しました。

---

## 🎯 実装内容

### 1. Stimulusコントローラー
**ファイル:** `app/javascript/controllers/loading_controller.js`

#### 機能:
- ✅ Turboイベント（`turbo:visit`, `turbo:submit-start`など）に自動連動
- ✅ ページ遷移開始時に自動表示
- ✅ ページ読み込み完了時に自動非表示
- ✅ フェードイン・フェードアウトアニメーション
- ✅ 既存の手動表示/非表示メソッドとの互換性維持

#### 監視するTurboイベント:

**表示トリガー:**
- `turbo:visit` - ページ遷移開始
- `turbo:submit-start` - フォーム送信開始
- `turbo:before-fetch-request` - データフェッチ開始

**非表示トリガー:**
- `turbo:load` - ページ読み込み完了
- `turbo:submit-end` - フォーム送信完了
- `turbo:frame-load` - Turbo Frameの読み込み完了

### 2. HTMLマークアップ
**ファイル:** `app/views/layouts/application.html.haml`

```haml
%body{ data: { controller: "loading" } }
  / ローディングオーバーレイ
  #loading-overlay.fixed.inset-0.bg-black.bg-opacity-40.hidden.items-center.justify-center.opacity-0.transition-opacity.duration-200{ data: { loading_target: "overlay" }, style: "z-index: 9999;" }
    .text-center
      / CSSスピナー
      .spinner.w-16.h-16.border-4.border-white.border-t-transparent.rounded-full.animate-spin.mx-auto
      / ローディングテキスト
      .text-white.text-lg.font-medium.mt-4 読み込み中...
```

#### 特徴:
- 画面全体を覆う固定配置（`fixed inset-0`）
- 半透明の黒背景（`bg-black bg-opacity-40`）
- 最前面表示（`z-index: 9999`）
- フレックスボックスで中央配置（`items-center justify-center`）
- Tailwindの`animate-spin`でスピナーアニメーション

### 3. CSSスタイル
**ファイル:** `app/assets/stylesheets/application.css`

#### カスタムスタイル:
- ✅ `backdrop-filter: blur(2px)` - 背景のブラー効果
- ✅ スピナーのボーダーアニメーション
- ✅ ダークモード対応
- ✅ サイズバリエーション（sm, lg）

---

## 🚀 使い方

### 自動動作（推奨）

Turboイベントに自動連動するため、**特別な設定は不要**です。

以下の操作で自動的にローディングが表示されます：
- リンクのクリック（ページ遷移）
- フォームの送信
- Turbo Frameの更新

### 手動制御（既存機能との互換性）

既存のコードとの互換性を維持するため、手動制御も可能です：

```javascript
// Stimulusコントローラーから
this.dispatch("loading:show")  // 表示
this.dispatch("loading:hide")  // 非表示

// または直接メソッドを呼び出す
const loadingController = this.application.getControllerForElementAndIdentifier(
  document.body, 
  "loading"
)
loadingController.show()  // 表示
loadingController.hide()  // 非表示
```

### ボタンの無効化（既存機能）

```haml
%button{ data: { loading_target: "button", action: "click->loading#show" } }
  送信
```

このボタンをクリックすると：
1. ローディングオーバーレイが表示される
2. ボタンが無効化される
3. ボタンテキストが「送信中...」に変更される

---

## 🎨 カスタマイズ

### 背景色の変更

```haml
/ 白系の半透明背景
#loading-overlay.fixed.inset-0.bg-white.bg-opacity-70...

/ より濃い背景
#loading-overlay.fixed.inset-0.bg-black.bg-opacity-60...
```

### スピナーの色変更

```haml
/ 青いスピナー
.spinner.w-16.h-16.border-4.border-blue-200.border-t-blue-600...

/ 緑のスピナー
.spinner.w-16.h-16.border-4.border-green-200.border-t-green-600...
```

### スピナーのサイズ変更

```haml
/ 小さいスピナー
.spinner.spinner-sm

/ 大きいスピナー
.spinner.spinner-lg
```

### アニメーション速度の変更

`application.css`で調整：

```css
#loading-overlay .spinner {
  animation: spin 0.6s linear infinite; /* 速く */
}

#loading-overlay .spinner {
  animation: spin 1.2s linear infinite; /* 遅く */
}
```

### フェード時間の変更

`application.html.haml`で調整：

```haml
/ より速いフェード（100ms）
#loading-overlay.transition-opacity.duration-100...

/ より遅いフェード（500ms）
#loading-overlay.transition-opacity.duration-500...
```

---

## 🔧 トラブルシューティング

### ローディングが表示されない

**確認項目:**
1. Stimulusコントローラーが読み込まれているか
   ```javascript
   console.log("Loading controller connected") // コンソールに表示されるか
   ```

2. `#loading-overlay`要素が存在するか
   ```javascript
   console.log(document.getElementById("loading-overlay"))
   ```

3. Turboイベントが発火しているか
   ```javascript
   document.addEventListener("turbo:visit", () => console.log("turbo:visit"))
   ```

### ローディングが消えない

**原因:**
- JavaScriptエラーで`hideLoading`が呼ばれていない
- 無限ループや非同期処理の遅延

**解決方法:**
```javascript
// 開発者ツールのコンソールで手動で非表示
document.getElementById("loading-overlay").classList.add("hidden")
```

### ページ遷移時にチラつく

**原因:**
- アニメーションの遅延設定が長すぎる

**解決方法:**
```javascript
// loading_controller.jsで調整
setTimeout(() => {
  overlay.classList.remove("flex")
  overlay.classList.add("hidden")
}, 100) // 200ms → 100ms に短縮
```

---

## 📊 実装ファイル一覧

| ファイル | 説明 | 行数 |
|---------|------|------|
| `app/javascript/controllers/loading_controller.js` | Stimulusコントローラー | 96行 |
| `app/views/layouts/application.html.haml` | HTMLマークアップ | 8行追加 |
| `app/assets/stylesheets/application.css` | CSSスタイル | 47行追加 |

---

## ✨ 機能の特徴

- ✅ **完全自動**: Turboイベントに自動連動
- ✅ **連打防止**: z-index 9999で誤タップを防止
- ✅ **スムーズ**: フェードイン・アウトアニメーション
- ✅ **軽量**: CSSアニメーションのみ（JavaScriptライブラリ不要）
- ✅ **レスポンシブ**: 画面サイズに関係なく動作
- ✅ **ダークモード対応**: 自動的に背景色が調整される
- ✅ **互換性**: 既存コードとの互換性を維持

---

## 🎉 完了

これでページ遷移やフォーム送信時に自動的にローディングオーバーレイが表示されます！

**更新日:** 2026-07-21  
**バージョン:** 1.0
