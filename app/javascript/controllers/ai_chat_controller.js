import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { conversationId: String }
  static targets = [
    "messagesContainer", 
    "messageInput", 
    "submitButton", 
    "form", 
    "loadingIndicator",
    "modeBadge"
  ]

  get draftKey() {
    return `ai_chat_draft_${this.conversationIdValue}`
  }

  connect() {
    console.log("🤖 AI Chat controller connected!")
    console.log("Conversation ID:", this.conversationIdValue)

    // 保存済みのドラフトを復元
    const savedDraft = sessionStorage.getItem(this.draftKey)
    if (savedDraft) {
      this.messageInputTarget.value = savedDraft
    }
    
    // メッセージコンテナを最下部にスクロール
    this.scrollToBottom()
  }

  saveDraft() {
    const value = this.messageInputTarget.value
    if (value) {
      sessionStorage.setItem(this.draftKey, value)
    } else {
      sessionStorage.removeItem(this.draftKey)
    }
  }

  async sendMessage(event) {
    event.preventDefault()
    
    const message = this.messageInputTarget.value.trim()
    if (!message) return

    console.log("📤 Sending message:", message)
    
    // UIの準備
    this.showUserMessage(message)
    this.clearInput()
    this.showLoading(true)
    this.disableForm(true)

    try {
      const response = await fetch("/ai_secretary/send_message", {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: new URLSearchParams({
          message: message,
          conversation_id: this.conversationIdValue
        })
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const data = await response.json()
      
      if (data.status === "success") {
        console.log("✅ AI response received:", data.ai_response)
        this.showAiMessage(data.ai_response.content)
        this.updateModeBadge(data.active_mode)

        // カレンダー登録完了カードを表示
        if (data.calendar_event) {
          this.showCalendarEventCard(data.calendar_event)
        }
        
        // サイドバーの会話履歴を更新
        if (data.refresh_sidebar) {
          this.refreshConversationSidebar()
        }
      } else if (data.status === "document_generated") {
        console.log("📄 Document generated:", data)
        this.showAiMessage(data.ai_response.content, data.actions)
        this.updateModeBadge(data.active_mode)
        
        // サイドバーの会話履歴を更新
        if (data.refresh_sidebar) {
          this.refreshConversationSidebar()
        }
      } else {
        throw new Error(data.error || "Unknown error occurred")
      }
      
    } catch (error) {
      console.error("❌ AI Chat error:", error)
      this.showErrorMessage(`エラーが発生しました: ${error.message}`)
    } finally {
      this.showLoading(false)
      this.disableForm(false)
      this.messageInputTarget.focus()
    }
  }

  handleKeydown(event) {
    // Shift + Enter で送信
    if (event.key === "Enter" && event.shiftKey) {
      event.preventDefault()
      this.sendMessage(event)
    }
  }

  showUserMessage(content) {
    const messageHTML = `
      <div class="flex justify-end mb-4">
        <div class="max-w-xs lg:max-w-md px-4 py-2 bg-blue-500 text-white rounded-lg shadow">
          ${this.formatMessage(content)}
          <div class="text-xs text-blue-200 mt-1">${this.getCurrentTime()}</div>
        </div>
      </div>
    `
    this.addMessage(messageHTML)
  }

  showAiMessage(content, actions = null) {
    const actionsHTML = actions ? this.generateActionsHTML(actions) : ""
    const taskSuggestionHTML = this.detectTaskSuggestion(content) ? this.generateTaskSuggestionHTML(content) : ""
    
    const messageHTML = `
      <div class="flex justify-start mb-4">
        <div class="flex items-start space-x-2">
          <div class="bg-indigo-100 dark:bg-indigo-900 p-2 rounded-full flex-shrink-0">
            🤝
          </div>
          <div class="max-w-xs lg:max-w-md px-4 py-2 bg-white dark:bg-slate-700 text-gray-900 dark:text-slate-100 rounded-lg shadow border border-gray-200 dark:border-slate-600">
            ${this.formatMessage(content)}
            ${actionsHTML}
            ${taskSuggestionHTML}
            <div class="text-xs text-gray-500 dark:text-slate-400 mt-1">${this.getCurrentTime()}</div>
          </div>
        </div>
      </div>
    `
    this.addMessage(messageHTML)
  }

  // カレンダー登録完了カードを表示
  showCalendarEventCard(calendarEvent) {
    if (!calendarEvent.success) {
      const errorHTML = `
        <div class="flex justify-start mb-3">
          <div class="max-w-xs lg:max-w-md px-4 py-3 bg-red-50 dark:bg-red-900 border border-red-200 dark:border-red-700 rounded-xl shadow-sm">
            <div class="flex items-center space-x-2 mb-1">
              <span class="text-red-500">❌</span>
              <span class="text-xs font-semibold text-red-700 dark:text-red-300">カレンダー登録に失敗しました</span>
            </div>
            <p class="text-xs text-red-600 dark:text-red-400">${calendarEvent.error || calendarEvent.errors?.join(', ') || '不明なエラー'}</p>
          </div>
        </div>
      `
      this.addMessage(errorHTML)
      return
    }

    const ev = calendarEvent.event
    const cardHTML = `
      <div class="flex justify-start mb-3">
        <div class="max-w-xs lg:max-w-md px-4 py-3 bg-emerald-50 dark:bg-emerald-900 border border-emerald-200 dark:border-emerald-700 rounded-xl shadow-sm">
          <div class="flex items-center space-x-2 mb-2">
            <span class="text-emerald-600">📅</span>
            <span class="text-xs font-semibold text-emerald-700 dark:text-emerald-300">カレンダーに登録しました</span>
          </div>
          <div class="text-sm font-bold text-slate-800 dark:text-slate-100 mb-1">${ev.title}</div>
          <div class="text-xs text-slate-600 dark:text-slate-400 mb-3">🕐 ${ev.start_time} 〜 ${ev.end_time}</div>
          <a href="${ev.calendar_url}"
             class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-white bg-emerald-600 hover:bg-emerald-700 rounded-lg transition-colors">
            カレンダーで確認 →
          </a>
        </div>
      </div>
    `
    this.addMessage(cardHTML)
  }

  // モードバッジを更新
  updateModeBadge(mode) {
    if (!this.hasModeBadgeTarget) return
    const labels = {
      secretary: "🗂 秘書モード",
      welfare:   "🏥 MHSW相談モード",
      business:  "💼 ビジネス相談モード",
      mental:    "💆 メンタル管理モード"
    }
    const colors = {
      secretary: "bg-indigo-100 text-indigo-800 dark:bg-indigo-900 dark:text-indigo-200",
      welfare:   "bg-teal-100 text-teal-800 dark:bg-teal-900 dark:text-teal-200",
      business:  "bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200",
      mental:    "bg-pink-100 text-pink-800 dark:bg-pink-900 dark:text-pink-200"
    }
    const key = mode || "secretary"
    this.modeBadgeTarget.textContent = labels[key] || labels.secretary
    this.modeBadgeTarget.className = `px-2 py-0.5 text-xs rounded-full ${colors[key] || colors.secretary}`
  }

  // タスク登録提案の検出
  detectTaskSuggestion(content) {
    return /タスク.*登録しましょうか|タスクとして.*登録|→\s*タスク/.test(content)
  }

  // タスク登録提案ボタンHTML
  generateTaskSuggestionHTML(content) {
    return `
      <div class="mt-3 pt-3 border-t border-indigo-100 dark:border-slate-600">
        <p class="text-xs text-indigo-700 dark:text-indigo-300 mb-2">📌 タスクとして登録しますか？</p>
        <a href="/tasks/new" 
           class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-lg transition-colors">
          ✅ タスク登録画面へ
        </a>
      </div>
    `
  }

  generateActionsHTML(actions) {
    if (!actions || actions.length === 0) return ""
    
    const buttons = actions.map(action => `
      <a href="${action.url}?${new URLSearchParams(action.params).toString()}" 
         target="_blank"
         class="inline-flex items-center px-3 py-2 mr-2 mb-2 text-xs font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors">
        ${action.label}
      </a>
    `).join("")
    
    return `
      <div class="mt-3 pt-3 border-t border-gray-200 dark:border-slate-600">
        <p class="text-xs text-gray-600 dark:text-slate-400 mb-2">📄 生成された文書を保存しますか？</p>
        ${buttons}
      </div>
    `
  }

  showErrorMessage(content) {
    const messageHTML = `
      <div class="flex justify-center mb-4">
        <div class="max-w-xs lg:max-w-md px-4 py-2 bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200 rounded-lg shadow border border-red-200 dark:border-red-800">
          ❌ ${content}
          <div class="text-xs text-red-600 dark:text-red-400 mt-1">${this.getCurrentTime()}</div>
        </div>
      </div>
    `
    this.addMessage(messageHTML)
  }

  addMessage(messageHTML) {
    const chatMessages = document.getElementById("chat-messages")
    chatMessages.insertAdjacentHTML("beforeend", messageHTML)
    this.scrollToBottom()
  }

  clearInput() {
    this.messageInputTarget.value = ""
    this.messageInputTarget.style.height = "auto"
    sessionStorage.removeItem(this.draftKey)
  }

  showLoading(show) {
    if (show) {
      this.loadingIndicatorTarget.classList.remove("hidden")
    } else {
      this.loadingIndicatorTarget.classList.add("hidden")
    }
  }

  disableForm(disabled) {
    this.messageInputTarget.disabled = disabled
    this.submitButtonTarget.disabled = disabled
    
    if (disabled) {
      this.submitButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
    } else {
      this.submitButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
    }
  }

  formatMessage(content) {
    // 改行をbrタグに変換し、HTMLエスケープ
    return content
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#x27;")
      .replace(/\n/g, "<br>")
  }

  getCurrentTime() {
    const now = new Date()
    return now.toLocaleTimeString("ja-JP", { 
      hour: "2-digit", 
      minute: "2-digit" 
    })
  }

  scrollToBottom() {
    setTimeout(() => {
      this.messagesContainerTarget.scrollTop = this.messagesContainerTarget.scrollHeight
    }, 100)
  }

  // サイドバーの会話履歴を更新
  refreshConversationSidebar() {
    console.log("🔄 Refreshing conversation sidebar...")
    
    // conversation-sidebarコントローラーがあれば履歴をリロード
    const sidebarController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller*="conversation-sidebar"]'), 
      "conversation-sidebar"
    )
    
    if (sidebarController && typeof sidebarController.loadConversationList === 'function') {
      // 少し遅延してからリロード（レスポンス処理が完了してから）
      setTimeout(() => {
        sidebarController.loadConversationList()
      }, 500)
    } else {
      console.warn("⚠️ Conversation sidebar controller not found or loadConversationList method missing")
    }
  }
}