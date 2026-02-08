// app/javascript/controllers/sauna_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  activate() {
    // サウナ効果のアニメーション
    const messages = [
      "🔥 サウナで汗を流しています...",
      "💧 老廃物が排出されています...",
      "✨ 心身が浄化されています...",
      "🧘‍♂️ 整いました！"
    ]
    
    let currentIndex = 0
    const showMessage = () => {
      if (currentIndex < messages.length) {
        this.showFlash(messages[currentIndex], "success")
        currentIndex++
        setTimeout(showMessage, 1500)
      } else {
        // 最後にキャラクターの成長を表示
        this.showGrowthEffect()
      }
    }
    
    showMessage()
  }
  
  showGrowthEffect() {
    setTimeout(() => {
      this.showFlash("💪 精神的強靭さが大幅に向上しました！", "success")
      
      // キャラクター表示を更新（将来的にはTurbo Streamで）
      setTimeout(() => {
        this.showFlash("🌟 キャラクターが成長しています...", "info")
      }, 1000)
    }, 1000)
  }
  
  showFlash(message, type) {
    const flashContainer = document.getElementById("flash-messages")
    if (flashContainer) {
      const bgColor = type === "success" ? "bg-green-50 border-green-200 text-green-800 dark:bg-green-900 dark:border-green-700 dark:text-green-300" : "bg-blue-50 border-blue-200 text-blue-800 dark:bg-blue-900 dark:border-blue-700 dark:text-blue-300"
      
      const flashElement = document.createElement("div")
      flashElement.innerHTML = `
        <div class="flash-message border rounded-lg p-4 mb-4 animate-fade-in ${bgColor}"
             data-controller="flash" data-flash-timeout-value="3000">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="text-lg">🔥</span>
              <span class="text-sm font-medium">${message}</span>
            </div>
            <button class="text-lg opacity-70 hover:opacity-100 transition-opacity"
                    data-action="click->flash#close">×</button>
          </div>
        </div>
      `
      flashContainer.appendChild(flashElement.firstElementChild)
    }
  }
}