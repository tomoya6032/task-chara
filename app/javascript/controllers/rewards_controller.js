// app/javascript/controllers/rewards_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  show() {
    // ご褒美選択モーダルを表示
    const rewardOptions = [
      { type: "cake", emoji: "🍰", name: "甘いケーキ", effect: "内面の穏やかさ +5" },
      { type: "game", emoji: "🎮", name: "ゲーム時間", effect: "知性 +3, 内面の穏やかさ +2" },
      { type: "shopping", emoji: "🛍️", name: "ショッピング", effect: "内面の穏やかさ +3" },
      { type: "movie", emoji: "🎬", name: "映画鑑賞", effect: "内面の穏やかさ +7" },
      { type: "nature", emoji: "🌿", name: "自然散歩", effect: "全ステータス +2" },
      { type: "reading", emoji: "📚", name: "読書タイム", effect: "知性 +8" }
    ]

    const randomRewards = this.shuffleArray(rewardOptions).slice(0, 3)
    this.currentRewards = randomRewards
    
    this.showRewardModal(randomRewards)
  }

  showRewardModal(rewards) {
    const modalContent = `
      <div class="fixed inset-0 bg-black bg-opacity-30 backdrop-blur-sm z-50 flex items-center justify-center p-4">
        <div class="bg-white dark:bg-slate-800 bg-opacity-95 dark:bg-opacity-95 rounded-2xl shadow-2xl max-w-md w-full border border-slate-200 dark:border-slate-600 p-6">
          <div class="flex items-center justify-between mb-6">
            <h3 class="text-xl font-bold text-slate-900 dark:text-white">
              🎁 ご褒美を選んでください
            </h3>
            <button class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-300 text-2xl" onclick="window.closeRewardsModal()">×</button>
          </div>
          
          <div class="space-y-3 mb-6">
            ${rewards.map((reward, index) => `
              <button class="w-full p-4 text-left rounded-lg border border-slate-200 dark:border-slate-600 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors group"
                      onclick="window.selectReward(${index})">
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
        </div>
      </div>
    `

    // モーダルエリアに挿入
    const modalArea = document.getElementById('task-modal')
    if (modalArea) {
      modalArea.innerHTML = modalContent
      
      // グローバル関数を設定
      window.selectReward = (index) => {
        this.selectReward(index)
      }
      
      window.closeRewardsModal = () => {
        this.closeModal()
      }
    }
  }

  selectReward(index) {
    console.log('selectReward called with index:', index)
    console.log('currentRewards:', this.currentRewards)
    
    const selectedReward = this.currentRewards[index]
    console.log('selectedReward:', selectedReward)
    
    if (!selectedReward) {
      console.error('No reward found at index:', index)
      return
    }
    
    // バックエンドにご褒美選択を送信
    fetch('/rewards/claim', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'text/vnd.turbo-stream.html',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
      },
      body: JSON.stringify({
        reward_type: selectedReward.type
      })
    })
    .then(response => {
      console.log('Response status:', response.status)
      console.log('Response headers:', response.headers.get('Content-Type'))
      
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      return response.text();
    })
    .then(html => {
      console.log('Received HTML:', html.substring(0, 200))
      
      // Turbo Streamかどうかチェック
      if (html.includes('<turbo-stream')) {
        // Turbo Streamを実行
        if (window.Turbo && window.Turbo.renderStreamMessage) {
          window.Turbo.renderStreamMessage(html);
        } else {
          console.warn('Turbo not available, trying alternative method')
          // 代替方法でTurbo Streamを処理
          const parser = new DOMParser();
          const doc = parser.parseFromString(html, 'text/html');
          const streams = doc.querySelectorAll('turbo-stream');
          streams.forEach(stream => {
            const action = stream.getAttribute('action');
            const target = stream.getAttribute('target');
            const content = stream.innerHTML;
            
            if (action === 'update' && target) {
              const targetElement = document.getElementById(target);
              if (targetElement) {
                targetElement.innerHTML = content;
              }
            }
          });
        }
      }
      
      // モーダルを閉じる
      this.closeModal();
    })
    .catch(error => {
      console.error('Error:', error);
      alert('ご褒美の選択に失敗しました: ' + error.message);
    });
  }

  closeModal() {
    const modalArea = document.getElementById('task-modal')
    if (modalArea) {
      modalArea.innerHTML = ''
    }
    
    // グローバル関数をクリーンアップ
    if (window.selectReward) {
      delete window.selectReward
    }
    if (window.closeRewardsModal) {
      delete window.closeRewardsModal
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