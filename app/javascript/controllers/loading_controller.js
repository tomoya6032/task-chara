// app/javascript/controllers/loading_controller.js
import { Controller } from "@hotwired/stimulus"

// ページ遷移やフォーム送信時にローディングオーバーレイを表示するコントローラー
export default class extends Controller {
  static targets = ["overlay", "button"]

  connect() {
    console.log("Loading controller connected")
    
    // Turboイベントをリッスン
    this.boundShowLoading = this.showLoading.bind(this)
    this.boundHideLoading = this.hideLoading.bind(this)
    
    // ページ遷移開始時に表示
    document.addEventListener("turbo:visit", this.boundShowLoading)
    document.addEventListener("turbo:submit-start", this.boundShowLoading)
    document.addEventListener("turbo:before-fetch-request", this.boundShowLoading)
    
    // ページ読み込み完了時に非表示
    document.addEventListener("turbo:load", this.boundHideLoading)
    document.addEventListener("turbo:submit-end", this.boundHideLoading)
    document.addEventListener("turbo:frame-load", this.boundHideLoading)
    
    // 初期状態では非表示
    this.hideLoading()
  }

  disconnect() {
    // イベントリスナーをクリーンアップ
    document.removeEventListener("turbo:visit", this.boundShowLoading)
    document.removeEventListener("turbo:submit-start", this.boundShowLoading)
    document.removeEventListener("turbo:before-fetch-request", this.boundShowLoading)
    document.removeEventListener("turbo:load", this.boundHideLoading)
    document.removeEventListener("turbo:submit-end", this.boundHideLoading)
    document.removeEventListener("turbo:frame-load", this.boundHideLoading)
  }

  // 手動でローディングを表示（既存のメソッドとの互換性維持）
  show() {
    this.showLoading()
  }

  // 手動でローディングを非表示（既存のメソッドとの互換性維持）
  hide() {
    this.hideLoading()
  }

  showLoading(event) {
    console.log("Loading: show", event?.type || "manual")
    
    // オーバーレイを表示
    const overlay = this.hasOverlayTarget ? this.overlayTarget : document.getElementById("loading-overlay")
    if (overlay) {
      overlay.classList.remove("hidden")
      overlay.classList.add("flex")
      
      // フェードインアニメーション
      requestAnimationFrame(() => {
        overlay.classList.remove("opacity-0")
        overlay.classList.add("opacity-100")
      })
    }
    
    // ボタンを無効化（既存機能）
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = true
      const originalText = this.buttonTarget.textContent
      this.buttonTarget.dataset.originalText = originalText
      this.buttonTarget.textContent = "送信中..."
    }
  }

  hideLoading(event) {
    console.log("Loading: hide", event?.type || "manual")
    
    // オーバーレイを非表示
    const overlay = this.hasOverlayTarget ? this.overlayTarget : document.getElementById("loading-overlay")
    if (overlay) {
      // フェードアウトアニメーション
      overlay.classList.remove("opacity-100")
      overlay.classList.add("opacity-0")
      
      // アニメーション完了後に完全に非表示
      setTimeout(() => {
        overlay.classList.remove("flex")
        overlay.classList.add("hidden")
      }, 200) // 0.2秒のトランジション時間と同期
    }
    
    // ボタンを有効化（既存機能）
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = false
      const originalText = this.buttonTarget.dataset.originalText || "送信"
      this.buttonTarget.textContent = originalText
    }
  }
}