// app/javascript/controllers/range_slider_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display"]
  
  update(event) {
    const value = event.target.value
    if (this.hasDisplayTarget) {
      this.displayTarget.textContent = value
    }
  }
}