// app/javascript/controllers/flash_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: Number }
  
  connect() {
    if (this.timeoutValue > 0) {
      this.timeout = setTimeout(() => {
        this.close()
      }, this.timeoutValue)
    }
  }
  
  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }
  
  close() {
    this.element.style.transition = "opacity 0.3s ease-out"
    this.element.style.opacity = "0"
    
    setTimeout(() => {
      if (this.element.parentNode) {
        this.element.parentNode.removeChild(this.element)
      }
    }, 300)
  }
}