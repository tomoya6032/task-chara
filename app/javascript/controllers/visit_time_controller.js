// app/javascript/controllers/visit_time_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["startTime", "endTime", "duration", "durationText"]

  syncEndTime(event) {
    const startTime = event.target.value
    if (startTime && this.hasEndTimeTarget) {
      // 開始時刻と同じ値を終了時刻に設定
      this.endTimeTarget.value = startTime
      // 自動的に所要時間も計算
      this.calculateDuration()
    }
  }

  calculateDuration() {
    const startTime = this.hasStartTimeTarget ? this.startTimeTarget.value : document.querySelector('[data-visit-time-target="startTime"]')?.value
    const endTime = this.hasEndTimeTarget ? this.endTimeTarget.value : document.querySelector('[data-visit-time-target="endTime"]')?.value

    if (startTime && endTime) {
      const start = new Date(startTime)
      const end = new Date(endTime)
      
      if (end > start) {
        const diffMs = end - start
        const diffHours = Math.floor(diffMs / (1000 * 60 * 60))
        const diffMinutes = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60))
        
        let durationText = ""
        if (diffHours > 0) {
          durationText += `${diffHours}時間`
        }
        if (diffMinutes > 0) {
          durationText += `${diffMinutes}分`
        }
        if (durationText === "") {
          durationText = "0分"
        }
        
        if (this.hasDurationTarget) {
          this.durationTarget.style.display = "block"
          if (this.hasDurationTextTarget) {
            this.durationTextTarget.textContent = durationText
          }
        }
      } else if (end < start) {
        // 終了時間が開始時間より前の場合
        if (this.hasDurationTarget) {
          this.durationTarget.style.display = "block"
          if (this.hasDurationTextTarget) {
            this.durationTextTarget.textContent = "時間が逆転しています"
            this.durationTextTarget.style.color = "#dc2626" // red-600
          }
        }
      } else {
        // 開始時間と終了時間が同じ場合
        if (this.hasDurationTarget) {
          this.durationTarget.style.display = "block"
          if (this.hasDurationTextTarget) {
            this.durationTextTarget.textContent = "0分"
            this.durationTextTarget.style.color = "#1e40af" // blue-800
          }
        }
      }
    } else {
      // どちらかの時間が未入力の場合は非表示
      if (this.hasDurationTarget) {
        this.durationTarget.style.display = "none"
      }
    }
  }
}