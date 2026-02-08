// app/javascript/controllers/loading_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]
  
  show() {
    const overlay = document.getElementById("loading-overlay")
    if (overlay) {
      overlay.classList.remove("hidden")
    }
    
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = true
      this.buttonTarget.textContent = "送信中..."
    }
  }
  
  hide() {
    const overlay = document.getElementById("loading-overlay")
    if (overlay) {
      overlay.classList.add("hidden")
    }
    
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = false
      this.buttonTarget.textContent = "日報を投稿"
    }
  }
}