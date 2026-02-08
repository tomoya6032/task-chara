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
  
  close() {
    console.log("Modal close called") // デバッグ用
    this.element.innerHTML = ""
    document.body.style.overflow = "auto"
  }
  
  closeOnBackdrop(event) {
    if (event.target === this.element) {
      console.log("Modal close on backdrop") // デバッグ用
      this.close()
    }
  }
}