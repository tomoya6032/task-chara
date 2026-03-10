// app/javascript/controllers/success_modal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["countdown"]
  static values = { redirectUrl: String, redirectDelay: Number }

  connect() {
    this.startCountdown()
    this.setupAutoRedirect()
  }

  disconnect() {
    this.clearTimers()
  }

  startCountdown() {
    let remainingSeconds = this.redirectDelayValue / 1000
    
    this.countdownInterval = setInterval(() => {
      remainingSeconds--
      if (remainingSeconds > 0 && this.hasCountdownTarget) {
        this.countdownTarget.textContent = `${remainingSeconds}秒後に一覧ページに移動します...`
      } else {
        this.clearTimers()
      }
    }, 1000)
  }

  setupAutoRedirect() {
    this.redirectTimeout = setTimeout(() => {
      this.redirectNow()
    }, this.redirectDelayValue)
  }

  redirectNow() {
    this.clearTimers()
    if (this.redirectUrlValue) {
      // Turbo.visit を使ってスムーズにページ遷移
      window.Turbo.visit(this.redirectUrlValue)
    }
  }

  close() {
    this.clearTimers()
    this.element.remove()
  }

  stopPropagation(event) {
    // モーダル内クリック時の伝播を停止
    event.stopPropagation()
  }

  clearTimers() {
    if (this.countdownInterval) {
      clearInterval(this.countdownInterval)
      this.countdownInterval = null
    }
    if (this.redirectTimeout) {
      clearTimeout(this.redirectTimeout)
      this.redirectTimeout = null
    }
  }
}