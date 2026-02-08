// app/javascript/controllers/rewards_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  show() {
    // ご褒美選択モーダルを表示
    const rewardOptions = [
      { emoji: "🍰", name: "甘いケーキ", effect: "内面の穏やかさ +5" },
      { emoji: "🎮", name: "ゲーム時間", effect: "知性 +3, 休息効果" },
      { emoji: "🛍️", name: "ショッピング", effect: "テンション上昇" },
      { emoji: "🎬", name: "映画鑑賞", effect: "内面の穏やかさ +7" },
      { emoji: "🌿", name: "自然散歩", effect: "全ステータス +2" },
      { emoji: "📚", name: "読書タイム", effect: "知性 +8" }
    ]

    const randomRewards = this.shuffleArray(rewardOptions).slice(0, 3)
    
    this.showRewardModal(randomRewards)
  }

  showRewardModal(rewards) {
    const modalContent = `
      <div class="fixed inset-0 z-50 overflow-y-auto">
        <div class="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0">
          <div class="fixed inset-0 transition-opacity bg-gray-500 bg-opacity-75" data-action="click->modal#close"></div>
          
          <div class="inline-block w-full max-w-md p-6 my-8 overflow-hidden text-left align-middle transition-all transform bg-white dark:bg-slate-800 shadow-xl rounded-2xl">
            <div class="flex items-center justify-between mb-6">
              <h3 class="text-xl font-bold text-slate-900 dark:text-white">
                🎁 ご褒美を選んでください
              </h3>
              <button class="text-slate-400 hover:text-slate-600 text-xl" data-action="click->modal#close">×</button>
            </div>
            
            <div class="space-y-3 mb-6">
              ${rewards.map((reward, index) => `
                <button class="w-full p-4 text-left rounded-lg border border-slate-200 dark:border-slate-600 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors group"
                        data-action="click->rewards#select" data-reward-index="${index}">
                  <div class="flex items-center gap-4">
                    <span class="text-3xl">${reward.emoji}</span>
                    <div>
                      <div class="font-semibold text-slate-900 dark:text-white">${reward.name}</div>
                      <div class="text-sm text-slate-500 dark:text-slate-400">${reward.effect}</div>
                    </div>
                  </div>
                </button>
              `).join('')}
            </div>
            
            <div class="text-center">
              <button class="px-6 py-2 text-sm font-medium text-slate-600 dark:text-slate-400 hover:text-slate-800 dark:hover:text-slate-200 transition-colors"
                      data-action="click->modal#close">
                後で決める
              </button>
            </div>
          </div>
        </div>
      </div>
    `

    const modalFrame = document.getElementById("modal")
    modalFrame.innerHTML = modalContent
    modalFrame.classList.remove("hidden")
  }

  select(event) {
    const rewardIndex = event.currentTarget.dataset.rewardIndex
    
    // ご褒美選択のアニメーション
    this.showRewardAnimation()
    
    // モーダルを閉じる
    setTimeout(() => {
      const modalFrame = document.getElementById("modal")
      modalFrame.innerHTML = ""
      modalFrame.classList.add("hidden")
    }, 2000)
  }

  showRewardAnimation() {
    const messages = [
      "🎁 ご褒美を受け取りました！",
      "✨ キャラクターが成長しています...",
      "😊 満足度が向上しました！"
    ]
    
    let currentIndex = 0
    const showMessage = () => {
      if (currentIndex < messages.length) {
        this.showFlash(messages[currentIndex], "success")
        currentIndex++
        setTimeout(showMessage, 1000)
      }
    }
    
    showMessage()
  }

  showFlash(message, type) {
    const flashContainer = document.getElementById("flash-messages")
    if (flashContainer) {
      const flashElement = document.createElement("div")
      flashElement.innerHTML = `
        <div class="flash-message border rounded-lg p-4 mb-4 animate-fade-in bg-green-50 border-green-200 text-green-800 dark:bg-green-900 dark:border-green-700 dark:text-green-300"
             data-controller="flash" data-flash-timeout-value="2000">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="text-lg">🎁</span>
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

  shuffleArray(array) {
    const shuffled = [...array]
    for (let i = shuffled.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1))
      ;[shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]]
    }
    return shuffled
  }
}