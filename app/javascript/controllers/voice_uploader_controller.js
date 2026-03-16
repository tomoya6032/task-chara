// app/javascript/controllers/voice_uploader_controller.js
import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="voice-uploader"
export default class extends Controller {
  static targets = ["fileInput", "preview", "audio", "fileName", "status", "uploadButton", "cancelButton"]
  static values = { activityId: String }

  connect() {
    console.log("Voice uploader controller connected")
    console.log("Activity ID:", this.activityIdValue)
    console.log("Targets available:", this.targets)
    this.isProcessing = false
  }

  selectFile() {
    console.log("selectFile called")
    console.log("fileInputTarget:", this.fileInputTarget)
    this.fileInputTarget.click()
  }

  async handleFileSelect(event) {
    const file = event.target.files[0]
    if (!file) return

    // ファイルタイプをチェック
    if (!file.type.startsWith('audio/')) {
      alert('音声ファイルを選択してください')
      return
    }

    // ファイルサイズをチェック (25MB制限 - OpenAI Whisperの制限)
    if (file.size > 25 * 1024 * 1024) {
      alert('ファイルサイズは25MB以下にしてください')
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
    const audioUrl = URL.createObjectURL(file)
    
    this.audioTarget.src = audioUrl
    this.fileNameTarget.textContent = `ファイル名: ${file.name} (${this.formatFileSize(file.size)})`
    this.previewTarget.style.display = 'block'
  }

  formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes'
    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
  }

  async processAudio() {
    const file = this.fileInputTarget.files[0]
    if (!file) {
      alert('まず音声ファイルを選択してください')
      return
    }

    if (this.isProcessing) {
      console.log('Already processing, ignoring request')
      return
    }

    this.isProcessing = true

    // UI更新
    this.uploadButtonTarget.style.display = 'none'
    this.cancelButtonTarget.style.display = 'inline-flex'
    this.showLoading('音声ファイルをアップロードしています...')

    const formData = new FormData()
    formData.append('audio_file', file)

    try {
      const response = await fetch(`/activities/${this.activityIdValue}/process_voice_transcription`, {
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
        this.showLoading('🤖 AIが音声を文字起こししています...')
        console.log("Audio processing started, waiting for WebSocket result...")
      } else {
        throw new Error(result.message || '不明なエラーが発生しました')
      }

    } catch (error) {
      console.error('音声送信エラー:', error)
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
    loadingEl.id = 'voice-upload-loading'
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
    const existingLoading = document.getElementById('voice-upload-loading')
    if (existingLoading) {
      existingLoading.remove()
    }
  }

  cancelProcessing() {
    if (!this.isProcessing) return
    
    console.log('Audio processing cancelled by user')
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
}