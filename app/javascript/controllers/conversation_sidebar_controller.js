import { Controller } from "@hotwired/stimulus"

// 会話履歴サイドバーを管理するStimulusコントローラー
export default class extends Controller {
  static targets = ["conversationList", "searchInput", "conversationTitle"]
  static values = { currentConversationId: String }

  connect() {
    console.log("🗣️ Conversation sidebar controller connected")
    this.loadConversationList()
  }

  // 会話履歴を読み込み
  async loadConversationList() {
    try {
      console.log("🔄 Loading conversation list...")
      const response = await fetch("/ai_secretary/conversation_list", {
        method: "GET",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })

      console.log(`📡 Response status: ${response.status}`)

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const data = await response.json()
      console.log("📋 Conversation data:", data)
      
      if (data.error) {
        throw new Error(data.error)
      }
      
      this.displayConversations(data.conversations || [])
    } catch (error) {
      console.error("❌ Failed to load conversation list:", error)
      this.showConversationListError("会話履歴の読み込みに失敗しました: " + error.message)
    }
  }

  // 会話一覧を表示
  displayConversations(conversations) {
    if (!conversations || conversations.length === 0) {
      this.conversationListTarget.innerHTML = `
        <div class="text-center py-8 text-slate-500">
          <i class="fas fa-comments text-2xl mb-2"></i>
          <p class="text-sm">まだ会話がありません</p>
          <p class="text-xs mt-1">新しい会話を開始してください</p>
        </div>
      `
      return
    }

    const conversationHTML = conversations.map(conversation => `
      <div class="conversation-item p-3 rounded-lg cursor-pointer transition-colors hover:bg-slate-100 dark:hover:bg-slate-700 mb-2 ${
        conversation.is_current ? 'bg-blue-50 dark:bg-blue-900 border-l-4 border-blue-500' : 'bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-600'
      }" 
           data-conversation-id="${conversation.conversation_id}"
           data-action="click->conversation-sidebar#switchConversation">
        <div class="flex items-start justify-between">
          <div class="flex-1 min-w-0">
            <h4 class="text-sm font-medium text-slate-900 dark:text-white truncate mb-1">
              ${conversation.title}
            </h4>
            <p class="text-xs text-slate-500 dark:text-slate-400 line-clamp-2 mb-2">
              ${conversation.preview}
            </p>
            <div class="flex items-center justify-between text-xs text-slate-400">
              <span>${this.formatRelativeTime(conversation.last_message_at)}</span>
              <span class="flex items-center">
                <i class="fas fa-comments mr-1"></i>
                ${conversation.message_count}
              </span>
            </div>
          </div>
          ${conversation.is_current ? `
            <div class="ml-2 flex items-center">
              <div class="w-2 h-2 bg-blue-500 rounded-full"></div>
            </div>
          ` : ''}
        </div>
      </div>
    `).join('')

    this.conversationListTarget.innerHTML = conversationHTML
  }

  // エラー表示
  showConversationListError(message) {
    this.conversationListTarget.innerHTML = `
      <div class="text-center py-8 text-red-500">
        <i class="fas fa-exclamation-triangle text-2xl mb-2"></i>
        <p class="text-sm">${message}</p>
        <button class="mt-2 px-3 py-1 bg-red-100 text-red-700 rounded text-xs" 
                data-action="click->conversation-sidebar#loadConversationList">
          再試行
        </button>
      </div>
    `
  }

  // 新しい会話を開始
  async newConversation(event) {
    event.preventDefault()
    console.log("🆕 Starting new conversation")

    const button = event.currentTarget
    const originalText = button.innerHTML
    
    try {
      // ボタンローディング状態
      button.disabled = true
      button.innerHTML = '<i class="fas fa-spinner fa-spin"></i>'

      const response = await fetch("/ai_secretary/new_conversation", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const data = await response.json()
      
      if (data.success) {
        // 新しい会話のページにリダイレクト
        window.location.href = `/ai_secretary/chat?conversation_id=${data.conversation_id}`
      } else {
        throw new Error(data.error || "新しい会話の作成に失敗しました")
      }
    } catch (error) {
      console.error("❌ Failed to create new conversation:", error)
      this.showNotification(`エラー: ${error.message}`, "error")
    } finally {
      button.disabled = false
      button.innerHTML = originalText
    }
  }

  // 会話を切り替え
  switchConversation(event) {
    event.preventDefault()
    const conversationId = event.currentTarget.dataset.conversationId
    
    if (conversationId && conversationId !== this.currentConversationIdValue) {
      console.log(`🔄 Switching to conversation: ${conversationId}`)
      window.location.href = `/ai_secretary/chat?conversation_id=${conversationId}`
    }
  }

  // 会話をクリア
  async clearConversation(event) {
    event.preventDefault()
    
    if (!confirm("現在の会話をクリアしますか？この操作は元に戻せません。")) {
      return
    }

    console.log("🗑️ Clearing current conversation")
    
    // 新しい会話を開始することで実質的にクリア
    this.newConversation(event)
  }

  // 会話を検索/フィルタリング
  filterConversations(event) {
    const query = event.target.value.toLowerCase()
    const conversationItems = document.querySelectorAll('.conversation-item')

    conversationItems.forEach(item => {
      const title = item.querySelector('h4').textContent.toLowerCase()
      const preview = item.querySelector('p').textContent.toLowerCase()
      
      if (title.includes(query) || preview.includes(query)) {
        item.style.display = 'block'
      } else {
        item.style.display = 'none'
      }
    })
  }

  // 相対時間フォーマット
  formatRelativeTime(dateString) {
    const date = new Date(dateString)
    const now = new Date()
    const diffMs = now - date
    const diffMins = Math.floor(diffMs / 60000)
    const diffHours = Math.floor(diffMs / 3600000)
    const diffDays = Math.floor(diffMs / 86400000)

    if (diffMins < 1) return "今"
    if (diffMins < 60) return `${diffMins}分前`
    if (diffHours < 24) return `${diffHours}時間前`
    if (diffDays < 7) return `${diffDays}日前`
    
    return date.toLocaleDateString('ja-JP', { 
      month: 'short', 
      day: 'numeric' 
    })
  }

  // 会話タイトルを更新
  updateConversationTitle(title) {
    if (this.hasConversationTitleTarget) {
      this.conversationTitleTarget.textContent = title ? `- ${title}` : ""
    }
  }

  // 通知を表示
  showNotification(message, type = "success") {
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
    
    // クリックで削除
    notification.addEventListener('click', () => {
      notification.remove()
    })
  }

  disconnect() {
    console.log("🗣️ Conversation sidebar controller disconnected")
  }
}