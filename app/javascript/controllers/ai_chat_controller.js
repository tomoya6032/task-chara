import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { conversationId: String }
  static targets = [
    "messagesContainer", 
    "messageInput", 
    "submitButton", 
    "form", 
    "loadingIndicator"
  ]

  connect() {
    console.log("🤖 AI Chat controller connected!")
    console.log("Conversation ID:", this.conversationIdValue)
    
    // メッセージコンテナを最下部にスクロール
    this.scrollToBottom()
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
      } else if (data.status === "document_generated") {
        console.log("📄 Document generated:", data)
        this.showAiMessage(data.ai_response.content, data.actions)
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
    
    const messageHTML = `
      <div class="flex justify-start mb-4">
        <div class="flex items-start space-x-2">
          <div class="bg-gray-200 dark:bg-slate-700 p-2 rounded-full flex-shrink-0">
            🤖
          </div>
          <div class="max-w-xs lg:max-w-md px-4 py-2 bg-white dark:bg-slate-700 text-gray-900 dark:text-slate-100 rounded-lg shadow border border-gray-200 dark:border-slate-600">
            ${this.formatMessage(content)}
            ${actionsHTML}
            <div class="text-xs text-gray-500 dark:text-slate-400 mt-1">${this.getCurrentTime()}</div>
          </div>
        </div>
      </div>
    `
    this.addMessage(messageHTML)
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
}