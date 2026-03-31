// app/javascript/controllers/image_ocr_controller.js
import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="image-ocr"
export default class extends Controller {
  static targets = ["fileInput", "preview", "status", "uploadButton", "cancelButton"]
  static values = { activityId: String }

  connect() {
    console.log("Image OCR controller connected")
    this.isProcessing = false
  }

  selectFile() {
    this.fileInputTarget.click()
  }

  async handleFileSelect(event) {
    const file = event.target.files[0]
    if (!file) return

    // ファイルタイプをチェック
    if (!file.type.startsWith('image/')) {
      alert('画像ファイルを選択してください')
      return
    }

    // ファイルサイズをチェック (10MB制限)
    if (file.size > 10 * 1024 * 1024) {
      alert('ファイルサイズは10MB以下にしてください')
      return
    }

    // プレビュー表示
    this.showPreview(file)
    
    // アップロードボタンを表示
    this.uploadButtonTarget.style.display = 'inline-flex'
    this.statusTarget.textContent = '👆 「文字起こしを実行」ボタンを押してください'
    this.statusTarget.className = 'text-sm text-blue-600 font-medium'
  }

  showPreview(file) {
    const reader = new FileReader()
    reader.onload = (e) => {
      const img = document.createElement('img')
      img.src = e.target.result
      img.className = 'max-w-full max-h-32 object-contain rounded-md border'
      
      this.previewTarget.innerHTML = ''
      this.previewTarget.appendChild(img)
      this.previewTarget.style.display = 'block'
    }
    reader.readAsDataURL(file)
  }

  async processImage() {
    const file = this.fileInputTarget.files[0]
    if (!file) {
      alert('まず画像を選択してください')
      return
    }

    if (this.isProcessing) {
      console.log('Already processing, ignoring request')
      return
    }

    this.isProcessing = true

    // ローディング表示の実装
    this.showLoading('画像をアップロードしています...')
    
    // UI更新
    this.uploadButtonTarget.style.display = 'none'
    this.cancelButtonTarget.style.display = 'inline-flex'

    const formData = new FormData()
    formData.append('image_file', file)

    try {
      const response = await fetch(`/activities/${this.activityIdValue}/process_image_ocr`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.message || `HTTP ${response.status}`)
      }

      const result = await response.json()

      if (result.status === 'processing') {
        this.showLoading('🤖 AIが画像を解析しています...')
        console.log('OCR processing started, waiting for WebSocket result...')
      } else {
        throw new Error(result.message || '不明なエラーが発生しました')
      }

    } catch (error) {
      console.error('画像送信エラー:', error)
      this.hideLoading()
      this.showError('エラーが発生しました: ' + error.message)
      this.resetUI()
    }
  }

  showLoading(message) {
    // 既存のローディング表示があれば削除
    this.hideLoading()
    
    // ローディング表示を作成
    const loadingEl = document.createElement('div')
    loadingEl.id = 'image-ocr-loading'
    loadingEl.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50'
    loadingEl.innerHTML = `
      <div class="bg-white rounded-lg p-6 max-w-sm mx-4">
        <div class="flex items-center space-x-3">
          <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-600"></div>
          <span class="text-gray-700">${message}</span>
        </div>
      </div>
    `
    
    document.body.appendChild(loadingEl)
    
    // ステータスメッセージも更新
    this.statusTarget.textContent = `🔄 ${message}`
    this.statusTarget.className = 'text-sm text-blue-600 font-medium'
  }

  hideLoading() {
    const existingLoading = document.getElementById('image-ocr-loading')
    if (existingLoading) {
      existingLoading.remove()
    }
  }

  showError(message) {
    this.hideLoading()
    this.statusTarget.textContent = '❌ ' + message
    this.statusTarget.className = 'text-sm text-red-600'
    
    // エラーメッセージを3秒後に自動で隠す
    setTimeout(() => {
      this.statusTarget.textContent = ''
      this.statusTarget.className = 'text-sm text-gray-600'
    }, 3000)
  }

  cancelProcessing() {
    if (!this.isProcessing) return
    
    console.log('Processing cancelled by user')
    this.hideLoading()
    this.statusTarget.textContent = 'キャンセルされました'
    this.statusTarget.className = 'text-sm text-yellow-600 font-medium'
    this.resetUI()
    
    setTimeout(() => {
      this.statusTarget.textContent = ''
      this.statusTarget.className = 'text-sm text-gray-600'
    }, 2000)
  }

  resetUI() {
    this.isProcessing = false
    this.uploadButtonTarget.style.display = 'inline-flex'
    this.cancelButtonTarget.style.display = 'none'
    this.uploadButtonTarget.disabled = false
    this.uploadButtonTarget.textContent = '文字起こしを実行'
    this.hideLoading()
  }

  subscribeToOcrResults() {
    // WebSocketの結果はwebsocket-controllerで処理される
    // このメソッドは呼ばれなくなる予定だが、念のため維持
    console.log("OCR processing started, waiting for WebSocket result...")
  }

  // テスト用メソッド（開発環境でのみ使用）
  testInsert() {
    const testContent = '【業務報告】\n\n■ 活動概要\n利用者宅への定期訪問を実施。健康状態の確認と生活相談対応を行った。\n\n■ 相談内容\n・日常生活における移動支援について\n・介護保険サービス利用に関する質問\n\n■ 実施した対応\n・移動時の安全確保についてアドバイス\n・関係機関との連携について説明\n\n■ 今後の課題\n継続的な見守りとサポート体制の強化が必要'
    
    const textarea = document.getElementById('activity_content')
    if (textarea) {
      if (textarea.value.trim()) {
        textarea.value += '\n\n' + testContent
      } else {
        textarea.value = testContent
      }
      // character-counterがある場合は更新をトリガー
      textarea.dispatchEvent(new Event('input', { bubbles: true }))
    }
    
    this.statusTarget.textContent = '✅ テストデータを挿入しました'
    this.statusTarget.className = 'text-sm text-green-600 font-medium'
    
    setTimeout(() => {
      this.statusTarget.textContent = ''
      this.statusTarget.className = 'text-sm text-gray-600'
    }, 3000)
  }
}