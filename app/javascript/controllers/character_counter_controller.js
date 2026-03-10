// app/javascript/controllers/character_counter_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "counter"]

  connect() {
    this.updateCounter()
  }

  updateCounter() {
    if (this.hasTextareaTarget && this.hasCounterTarget) {
      const length = this.textareaTarget.value.length
      this.counterTarget.textContent = `${length}文字`
      
      if (length > 1000) {
        this.counterTarget.classList.add("text-red-500")
        this.counterTarget.classList.remove("text-gray-600")
      } else {
        this.counterTarget.classList.add("text-gray-600")
        this.counterTarget.classList.remove("text-red-500")
      }
    }
  }
}