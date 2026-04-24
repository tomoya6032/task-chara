import { Controller } from "@hotwired/stimulus"

// AIチャットから文書生成を行うStimulusコントローラー
export default class extends Controller {
  static targets = ["result", "content"]
  
  connect() {
    console.log("GenerateFromChats Controller connected")
  }

  // 会話を選択
  selectConversation(event) {
    event.preventDefault()
    // 他の選択された会話のハイライトを削除
    document.querySelectorAll('[data-conversation-id]').forEach(el => {
      el.classList.remove('bg-purple-100', 'border-purple-400')
      el.classList.add('bg-white', 'border-purple-200')
    })
    
    // 選択された会話をハイライト
    event.currentTarget.classList.remove('bg-white', 'border-purple-200')
    event.currentTarget.classList.add('bg-purple-100', 'border-purple-400')
    
    this.selectedConversationId = event.currentTarget.dataset.conversationId
    console.log(`Selected conversation: ${this.selectedConversationId}`)
  }

  // AIチャットから文書を生成
  async generateFromChat(event) {
    event.preventDefault()
    event.stopPropagation() // 親要素のクリックイベント防止
    
    const conversationId = event.currentTarget.dataset.conversationId
    const button = event.currentTarget
    const originalText = button.innerHTML
    
    if (!conversationId) {
      this.showError("会話IDが見つかりません")
      return
    }

    try {
      // ボタンローディング状態
      button.disabled = true
      button.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i>生成中...'
      
      // 現在のページに応じてエンドポイントを決定
      const currentPath = window.location.pathname
      let endpoint
      
      if (currentPath.includes('/meeting_minutes')) {
        endpoint = '/meeting_minutes/generate_from_chat'
      } else if (currentPath.includes('/activities')) {
        endpoint = '/activities/generate_from_chat'  
      } else if (currentPath.includes('/support_reports')) {
        endpoint = '/support_reports/generate_from_chat'
      } else {
        throw new Error('対応していないページです')
      }
      
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          conversation_id: conversationId
        })
      })

      const data = await response.json()
      
      if (response.ok) {
        this.showGeneratedContent(data.content)
        this.showSuccess(data.message || '生成が完了しました')
      } else {
        this.showError(data.error || '生成に失敗しました')
      }
    } catch (error) {
      console.error('Generation error:', error)
      this.showError(`エラーが発生しました: ${error.message}`)
    } finally {
      // ボタンを元に戻す
      button.disabled = false
      button.innerHTML = originalText
    }
  }

  // 生成されたコンテンツを表示
  showGeneratedContent(content) {
    const resultArea = document.getElementById('chat-generation-result')
    const textarea = document.getElementById('generated-content')
    
    if (resultArea && textarea) {
      textarea.value = content
      resultArea.classList.remove('hidden')
      
      // スムーズスクロール
      resultArea.scrollIntoView({ 
        behavior: 'smooth', 
        block: 'center' 
      })
    }
  }

  // 生成されたコンテンツをフォームに適用
  applyToForm(event) {
    event.preventDefault()
    
    const generatedContent = document.getElementById('generated-content').value
    const contentField = document.querySelector('textarea[name*="content"]')
    
    if (contentField && generatedContent) {
      // 既存のコンテンツがある場合は確認
      if (contentField.value.trim() && !confirm('既存の内容を置き換えますか？')) {
        return
      }
      
      contentField.value = generatedContent
      contentField.focus()
      
      // 成功フィードバック
      this.showSuccess('内容を適用しました')
      
      // 結果エリアを隠す（オプション）
      setTimeout(() => {
        const resultArea = document.getElementById('chat-generation-result')
        if (resultArea) {
          resultArea.classList.add('hidden')
        }
      }, 2000)
    }
  }

  // 成功メッセージを表示
  showSuccess(message) {
    this.showNotification(message, 'success')
  }

  // エラーメッセージを表示
  showError(message) {
    this.showNotification(message, 'error')
  }

  // 通知を表示
  showNotification(message, type = 'success') {
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 px-4 py-3 rounded-lg shadow-lg text-white text-sm font-medium ${
      type === 'success' ? 'bg-green-600' : 'bg-red-600'
    }`
    notification.innerHTML = `
      <div class="flex items-center">
        <i class="fas ${type === 'success' ? 'fa-check-circle' : 'fa-exclamation-triangle'} mr-2"></i>
        <span>${message}</span>
      </div>
    `
    
    document.body.appendChild(notification)
    
    // 3秒後に自動削除
    setTimeout(() => {
      notification.remove()
    }, 3000)
    
    // クリックで即座に削除
    notification.addEventListener('click', () => {
      notification.remove()
    })
  }
}