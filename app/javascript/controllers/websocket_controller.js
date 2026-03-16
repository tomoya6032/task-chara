// app/javascript/controllers/websocket_controller.js
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// グローバルな結果処理関数
window.handleAiProcessingResult = function(data) {
  console.log("🌟 === GLOBAL HANDLER TRIGGERED ===")
  console.log("Received data:", data)
  console.log("Data type:", data.type)
  console.log("Data status:", data.status)
  console.log("Content length:", data.content ? data.content.length : 0)
  
  // 最初にローディング画面を非表示
  hideAllLoadingScreens()
  
  if (data.status === 'completed' && data.content) {
    console.log("✅ Processing completed data with content")
    
    // テキストエリアを複数の方法で検索
    let contentField = null
    const selectors = [
      'textarea[name="activity[content]"]',
      '#activity_content',
      'textarea[data-character-counter-target="input"]',
      'textarea[data-character-counter-target="textarea"]',
      'textarea[required]' // 必須フィールドとして検索
    ]
    
    console.log("🔍 Searching for content field...")
    for (let i = 0; i < selectors.length; i++) {
      console.log(`Trying selector ${i + 1}: ${selectors[i]}`)
      contentField = document.querySelector(selectors[i])
      if (contentField) {
        console.log(`✅ Found content field with selector: ${selectors[i]}`)
        break
      }
    }
    
    if (contentField) {
      console.log("📝 Inserting text into content field...")
      
      const currentText = contentField.value.trim()
      const separator = currentText ? '\n\n' : ''
      const newValue = currentText + separator + data.content
      
      console.log("Current text length:", currentText.length)
      console.log("New content length:", data.content.length)
      console.log("Final text length:", newValue.length)
      
      contentField.value = newValue
      
      // イベント発火
      const event = new Event('input', { bubbles: true })
      contentField.dispatchEvent(event)
      
      // フォーカス
      contentField.focus()
      contentField.setSelectionRange(contentField.value.length, contentField.value.length)
      
      // 成功通知
      const message = data.type === 'image_ocr' ? '📷 画像から文字を抽出しました！' : '🎤 音声をテキストに変換しました！'
      showSuccessNotification(message)
      
      // AIコントローラーのUIをリセット
      resetAllAiControllers('success', 'テキストが挿入されました')
      
      console.log("✅ Text successfully inserted into content field")
    } else {
      console.error("❌ Content field not found!")
      console.log("Available textareas on page:")
      const allTextareas = document.querySelectorAll('textarea')
      allTextareas.forEach((textarea, index) => {
        console.log(`Textarea ${index}:`)
        console.log(`  - name: ${textarea.name}`)
        console.log(`  - id: ${textarea.id}`)
        console.log(`  - class: ${textarea.className}`)
        console.log(`  - required: ${textarea.required}`)
      })
      
      resetAllAiControllers('error', 'テキストエリアが見つかりませんでした')
    }
  } else {
    console.warn("⚠️ Data incomplete:", {
      status: data.status,
      hasContent: !!data.content,
      contentPreview: data.content ? data.content.substring(0, 50) : 'No content'
    })
    
    resetAllAiControllers('error', data.error || '処理中にエラーが発生しました')
  }
}

// Connects to data-controller="websocket"
export default class extends Controller {
  static values = { activityId: String }

  connect() {
    console.log("=== WebSocket Controller Connected ===")
    console.log("Activity ID value:", this.activityIdValue)
    console.log("Element:", this.element)
    
    this.consumer = createConsumer()
    this.subscription = null
    this.subscribeToChannel()
    
    // 動的IDの場合の追加サブスクリプション
    if (this.activityIdValue === 'new') {
      this.setupDynamicIdListener()
    }
  }

  disconnect() {
    if (this.subscription) {
      this.consumer.subscriptions.remove(this.subscription)
    }
  }

  subscribeToChannel() {
    console.log("=== Subscribing to WebSocket Channel ===")
    console.log("Activity ID:", this.activityIdValue)
    console.log("Channel name: AiProcessingChannel")
    
    const self = this // thisのコンテキストを保持
    
    this.subscription = this.consumer.subscriptions.create(
      { 
        channel: "AiProcessingChannel", 
        activity_id: this.activityIdValue 
      },
      {
        connected() {
          console.log("✅ Connected to AI processing channel for activity:", self.activityIdValue)
        },

        disconnected() {
          console.log("❌ Disconnected from AI processing channel")
        },

        received(data) {
          console.log("📨 WEBSOCKET DATA RECEIVED ===")
          console.log("Raw data:", data)
          console.log("Data type:", data.type)
          console.log("Data status:", data.status)
          console.log("Data content preview:", data.content ? data.content.substring(0, 100) + "..." : "No content")
          
          // グローバル関数を使用（メイン処理）
          window.handleAiProcessingResult(data)
          // 従来の処理も継続（デバッグ用）
          self.handleAiResult(data)
        }
      }
    )
  }
  
  // 動的IDリスナーの設定（新規作成時）
  setupDynamicIdListener() {
    console.log("=== Setting up dynamic ID listener ===")
    
    // すべての可能なチャンネルをリッスンするためのワイルドカード的アプローチ
    const dynamicSubscription = this.consumer.subscriptions.create(
      { 
        channel: "AiProcessingChannel", 
        activity_id: "new_*" // サーバー側で動的IDをサポート
      },
      {
        connected() {
          console.log("✅ Connected to dynamic ID channel")
        },
        received(data) {
          console.log("📨 DYNAMIC CHANNEL RECEIVED:")
          console.log(data)
          window.handleAiProcessingResult(data)
        }
      }
    )
  }

  handleAiResult(data) {
    console.log("=== Handling AI Result ===")
    console.log("Data:", data)
    console.log("Data type:", data.type)
    console.log("Data status:", data.status)
    
    const { type, status, content, error } = data

    if (type === 'image_ocr') {
      this.handleOcrResult(status, content, error)
    } else if (type === 'voice_transcription') {
      this.handleVoiceResult(status, content, error)
    }
    
    // 処理完了時の追加フィードバック
    if (status === 'completed' && content) {
      this.showSuccessNotification(type)
    }
  }
  
  showSuccessNotification(type) {
    const message = type === 'image_ocr' ? '📷 画像から文字を抽出しました！' : '🎤 音声をテキストに変換しました！'
    
    // 成功通知を表示
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 bg-green-500 text-white px-6 py-3 rounded-lg shadow-lg z-50 flex items-center space-x-2'
    notification.innerHTML = `
      <span>${message}</span>
      <button onclick="this.parentElement.remove()" class="text-white hover:text-gray-200">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
        </svg>
      </button>
    `
    
    document.body.appendChild(notification)
    
    // 5秒後に自動で消す
    setTimeout(() => {
      if (notification.parentElement) {
        notification.remove()
      }
    }, 5000)
  }

  handleOcrResult(status, content, error) {
    const ocrController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller~="image-ocr"]'), 
      'image-ocr'
    )

    if (ocrController) {
      const statusElement = ocrController.statusTarget

      if (status === 'completed' && content) {
        // 成功時: contentフィールドにテキストを追加
        this.appendToContentField(content)
        statusElement.textContent = '✅ 画像からテキストを抽出しました'
        statusElement.className = 'text-sm text-green-600 font-medium'

        // UI をリセット
        setTimeout(() => {
          ocrController.resetUI()
          
          setTimeout(() => {
            statusElement.textContent = ''
            ocrController.previewTarget.style.display = 'none'
            ocrController.fileInputTarget.value = ''
          }, 3000)
        }, 1000)

      } else if (status === 'error') {
        statusElement.textContent = '❌ ' + (error || 'エラーが発生しました')
        statusElement.className = 'text-sm text-red-600'
        
        ocrController.resetUI()
      }
    }
  }

  handleVoiceResult(status, content, error) {
    // 音声録音コントローラーをチェック
    const voiceRecorderController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller~="voice-recorder"]'), 
      'voice-recorder'
    )
    
    // 音声アップローダーコントローラーをチェック
    const voiceUploaderController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller~="voice-uploader"]'), 
      'voice-uploader'
    )

    const activeController = voiceRecorderController || voiceUploaderController
    if (activeController) {
      const statusElement = activeController.statusTarget

      if (status === 'completed' && content) {
        // 成功時: contentフィールドにテキストを追加
        this.appendToContentField(content)
        statusElement.textContent = '✅ 音声をテキストに変換しました'
        statusElement.className = 'text-sm text-green-600 font-medium'

        // 処理状態をリセット
        if (activeController.resetProcessingState) {
          activeController.resetProcessingState()
        }

        // 音声アップローダーの場合はUIをリセット
        if (voiceUploaderController && voiceUploaderController.resetUI) {
          setTimeout(() => {
            voiceUploaderController.resetUI()
            
            setTimeout(() => {
              statusElement.textContent = ''
              voiceUploaderController.previewTarget.style.display = 'none'
              voiceUploaderController.fileInputTarget.value = ''
            }, 3000)
          }, 1000)
        } else {
          setTimeout(() => {
            statusElement.textContent = ''
          }, 5000)
        }

      } else if (status === 'error') {
        statusElement.textContent = '❌ ' + (error || 'エラーが発生しました')
        statusElement.className = 'text-sm text-red-600'
        
        // 処理状態をリセット
        if (activeController.resetProcessingState) {
          activeController.resetProcessingState()
        }

        // 音声アップローダーの場合はUIをリセット
        if (voiceUploaderController && voiceUploaderController.resetUI) {
          voiceUploaderController.resetUI()
        }
      }
    }
  }

  appendToContentField(newText) {
    console.log("=== Attempting to append text to content field ===")
    console.log("New text:", newText)
    
    // 複数の方法でコンテンツフィールドを探す
    let contentField = document.querySelector('textarea[name="activity[content]"]')
    
    if (!contentField) {
      contentField = document.getElementById('activity_content')
    }
    
    if (!contentField) {
      contentField = document.querySelector('textarea[data-character-counter-target="input"]')
    }
    
    if (!contentField) {
      contentField = document.querySelector('textarea[data-character-counter-target="textarea"]')
    }
    
    console.log("Found content field:", contentField)
    
    if (contentField) {
      const currentText = contentField.value.trim()
      const separator = currentText ? '\n\n' : ''
      const newValue = currentText + separator + newText
      
      console.log("Current text length:", currentText.length)
      console.log("New value length:", newValue.length)
      
      contentField.value = newValue
      
      // 文字数カウンターを更新
      const event = new Event('input', { bubbles: true })
      contentField.dispatchEvent(event)
      
      // フィールドにフォーカスを当てる
      contentField.focus()
      contentField.setSelectionRange(contentField.value.length, contentField.value.length)
      
      console.log("✅ Text successfully appended to content field")
    } else {
      console.error("❌ Content field not found! Available textareas:")
      const allTextareas = document.querySelectorAll('textarea')
      allTextareas.forEach((textarea, index) => {
        console.log(`Textarea ${index}:`, textarea)
        console.log(`  - name: ${textarea.name}`)
        console.log(`  - id: ${textarea.id}`)
        console.log(`  - class: ${textarea.className}`)
      })
    }
  }
}

// ヘルパー関数を追加
function hideAllLoadingScreens() {
  const loadingScreens = [
    document.getElementById('image-ocr-loading'),
    document.getElementById('voice-upload-loading')
  ]
  
  loadingScreens.forEach(screen => {
    if (screen) {
      screen.remove()
      console.log('Removed loading screen:', screen.id)
    }
  })
}

function showSuccessNotification(message) {
  const notification = document.createElement('div')
  notification.className = 'fixed top-4 right-4 bg-green-500 text-white px-6 py-3 rounded-lg shadow-lg z-50'
  notification.textContent = message
  document.body.appendChild(notification)
  
  setTimeout(() => {
    if (notification.parentElement) {
      notification.remove()
    }
  }, 5000)
}

function resetAllAiControllers(type, message) {
  const imageController = document.querySelector('[data-controller="image-ocr"]')
  const voiceController = document.querySelector('[data-controller="voice-uploader"]')
  
  if (imageController && window.application) {
    const controller = window.application.getControllerForElementAndIdentifier(imageController, 'image-ocr')
    if (controller && controller.statusTarget) {
      if (type === 'success') {
        controller.statusTarget.textContent = '✅ ' + message
        controller.statusTarget.className = 'text-sm text-green-600 font-medium'
      } else {
        controller.statusTarget.textContent = '❌ ' + message
        controller.statusTarget.className = 'text-sm text-red-600 font-medium'
      }
      controller.resetUI()
      
      // 2秒後にステータスメッセージをクリア
      setTimeout(() => {
        if (controller.statusTarget) {
          controller.statusTarget.textContent = ''
          controller.statusTarget.className = 'text-sm text-gray-600'
        }
      }, 2000)
    }
  }
  
  if (voiceController && window.application) {
    const controller = window.application.getControllerForElementAndIdentifier(voiceController, 'voice-uploader')
    if (controller && controller.statusTarget) {
      if (type === 'success') {
        controller.statusTarget.textContent = '✅ ' + message
        controller.statusTarget.className = 'text-sm text-green-600 font-medium'
      } else {
        controller.statusTarget.textContent = '❌ ' + message
        controller.statusTarget.className = 'text-sm text-red-600 font-medium'
      }
      controller.resetUI()
      
      // 2秒後にステータスメッセージをクリア
      setTimeout(() => {
        if (controller.statusTarget) {
          controller.statusTarget.textContent = ''
          controller.statusTarget.className = 'text-sm text-gray-600'
        }
      }, 2000)
    }
  }
}