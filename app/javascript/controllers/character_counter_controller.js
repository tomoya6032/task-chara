// app/javascript/controllers/character_counter_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "counter"]

  connect() {
    this.updateCounter()
    this.inputTarget.addEventListener("input", () => this.updateCounter())
  }

  updateCounter() {
    const length = this.inputTarget.value.length
    this.counterTarget.textContent = `${length}文字`
    
    // 文字数に応じて色を変える
    if (length < 50) {
      this.counterTarget.className = "text-xs text-red-500"
    } else if (length < 200) {
      this.counterTarget.className = "text-xs text-yellow-500"
    } else {
      this.counterTarget.className = "text-xs text-green-500"
    }
  }
}