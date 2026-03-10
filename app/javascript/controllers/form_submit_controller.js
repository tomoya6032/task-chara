// app/javascript/controllers/form_submit_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submitButton"]

  handleSubmit(event) {
    if (this.hasSubmitButtonTarget) {
      // ボタンを無効化してローディング状態に変更
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.innerHTML = `
        <i class="fas fa-spinner fa-spin mr-2"></i>
        投稿中...
      `
      this.submitButtonTarget.classList.add("opacity-75", "cursor-not-allowed")
      
      // フォーム送信を実行
      this.element.requestSubmit()
    }
  }

  // フォーム送信後にボタンを元に戻す（エラー時などのため）
  resetSubmitButton() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = false
      this.submitButtonTarget.innerHTML = "投稿する"
      this.submitButtonTarget.classList.remove("opacity-75", "cursor-not-allowed")
    }
  }
}