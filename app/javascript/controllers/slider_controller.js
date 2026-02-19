// app/javascript/controllers/slider_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["value"]

  connect() {
    this.update()
  }

  update(event) {
    const slider = event ? event.target : this.element.querySelector('input[type="range"]')
    if (slider && this.hasValueTarget) {
      this.valueTarget.textContent = slider.value
    }
  }
}