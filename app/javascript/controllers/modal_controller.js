// app/javascript/controllers/modal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]
  
  connect() {
    console.log("Modal controller connected") // デバッグ用
    this.element.classList.remove("hidden")
    document.body.style.overflow = "hidden"
  }
  
  disconnect() {
    console.log("Modal controller disconnected") // デバッグ用
    document.body.style.overflow = "auto"
  }
  
  close(event) {
    if (event) event.preventDefault()
    console.log("Modal close called") // デバッグ用
    this.element.innerHTML = ""
    document.body.style.overflow = "auto"
  }
  
  closeOnBackdrop(event) {
    console.log("Modal close on backdrop clicked, target:", event.target, "element:", this.element) // デバッグ用
    // モーダルの背景（最外側の要素）がクリックされた場合のみ閉じる
    if (event.target === event.currentTarget) {
      console.log("Modal close on backdrop - closing") // デバッグ用
      this.close(event)
    }
  }
}