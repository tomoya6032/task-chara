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

    console.log('Voice file selected:', file.name, file.type, file.size)

    // 強化されたM4A対応のファイル形式チェック - 拡張子優先判定
    const fileExtension = file.name.split('.').pop().toLowerCase()
    const allowedExtensions = ['mp3', 'wav', 'm4a', 'webm', 'aac', 'ogg', 'mp4']
    const allowedTypes = [
      'audio/mp3', 'audio/mpeg',  // MP3
      'audio/wav', 'audio/x-wav',              // WAV
      'audio/m4a', 'audio/x-m4a', 'audio/mp4', 'audio/aac',  // M4A/AAC (iPhone標準)
      'audio/webm',               // WebM
      'audio/ogg',                // OGG
      'application/octet-stream', // 汎用バイナリ（一部デバイスでM4Aがこう報告される）
      ''                          // 空のMIMEタイプ（一部ブラウザで発生）
    ]
    
    // M4A特化処理：拡張子が.m4aなら常に有効とする
    const isM4AFile = fileExtension === 'm4a'
    const isMimeTypeValid = allowedTypes.includes(file.type)
    const isExtensionValid = allowedExtensions.includes(fileExtension)
    
    // M4Aファイルの場合はMIMEタイプに関係なく処理を続行
    const isValidType = isM4AFile || isMimeTypeValid || isExtensionValid
    
    console.log('File validation:', {
      fileName: file.name,
      mimeType: file.type || 'EMPTY/UNKNOWN',
      extension: fileExtension,
      isM4AFile: isM4AFile,
      isMimeTypeValid: isMimeTypeValid,
      isExtensionValid: isExtensionValid,
      finalValidation: isValidType
    })
    
    if (!isValidType) {
      alert(`サポートされていないファイル形式です\n対応形式：MP3、WAV、M4A、WebM、AAC、OGG\n検出形式：${file.type || '不明'} (.${fileExtension})`)
      return
    }
    
    // M4Aファイルは特別扱い - MIMEタイプが空でも処理続行
    if (isM4AFile) {
      console.log('🎵 M4A file confirmed - processing regardless of MIME type')
    }

    // ファイルサイズをチェック (50MBまで受付、25MB超はサーバー側で分割処理)
    if (file.size > 50 * 1024 * 1024) {
      alert(`ファイルサイズは50MB以下にしてください\n現在のサイズ：${(file.size/1024/1024).toFixed(2)}MB`)
      return
    }

    // プレビュー表示
    this.showPreview(file)
    
    // アップロードボタンを表示
    this.uploadButtonTarget.style.display = 'inline-flex'
    this.statusTarget.textContent = '👆 「文字起こしを実行」ボタンを押してください'
    this.statusTarget.className = 'text-sm text-blue-600 font-medium'
    
    console.log('✅ Voice file ready for processing')
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
          <div class="min-w-0 flex-1">
            <div id="voice-upload-loading-message" class="text-gray-700 text-sm font-medium">${message}</div>
            <div id="voice-upload-loading-progress" class="mt-2 hidden">
              <div class="h-2 w-full rounded-full bg-gray-200 overflow-hidden">
                <div id="voice-upload-loading-progress-bar" class="h-full bg-blue-600 rounded-full transition-all duration-300" style="width: 0%"></div>
              </div>
              <div id="voice-upload-loading-progress-text" class="mt-1 text-xs text-gray-500"></div>
            </div>
          </div>
        </div>
      </div>
    `
    
    document.body.appendChild(loadingEl)
    
    // ステータスメッセージも更新
    this.statusTarget.textContent = `🔄 ${message}`
    this.statusTarget.className = 'text-sm text-blue-600 font-medium'
  }

  updateLoadingProgress({ message, currentChunk, totalChunks, percent }) {
    const loadingEl = document.getElementById('voice-upload-loading')
    if (!loadingEl) {
      this.showLoading(message || '🤖 AIが音声を文字起こししています...')
    }

    const messageEl = document.getElementById('voice-upload-loading-message')
    const progressWrap = document.getElementById('voice-upload-loading-progress')
    const progressBar = document.getElementById('voice-upload-loading-progress-bar')
    const progressText = document.getElementById('voice-upload-loading-progress-text')

    if (messageEl && message) {
      messageEl.textContent = message
    }

    const hasChunkInfo = Number.isFinite(Number(currentChunk)) && Number.isFinite(Number(totalChunks)) && Number(totalChunks) > 0
    const hasPercent = Number.isFinite(Number(percent))

    if (progressWrap) {
      progressWrap.classList.remove('hidden')
    }

    if (progressBar) {
      const safePercent = hasPercent ? Math.max(0, Math.min(100, Number(percent))) : (hasChunkInfo ? Math.round((Number(currentChunk) / Number(totalChunks)) * 100) : 0)
      progressBar.style.width = `${safePercent}%`
    }

    if (progressText) {
      if (hasChunkInfo) {
        progressText.textContent = `${Number(currentChunk)}/${Number(totalChunks)}${hasPercent ? ` (${Math.max(0, Math.min(100, Number(percent)))}%)` : ''}`
      } else if (hasPercent) {
        progressText.textContent = `${Math.max(0, Math.min(100, Number(percent)))}%`
      } else {
        progressText.textContent = ''
      }
    }

    const statusParts = ['🔄']
    if (message) statusParts.push(message)
    if (hasChunkInfo) {
      statusParts.push(`${Number(currentChunk)}/${Number(totalChunks)}`)
    } else if (hasPercent) {
      statusParts.push(`${Math.max(0, Math.min(100, Number(percent)))}%`)
    }
    this.statusTarget.textContent = statusParts.join(' ')
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

  // テスト用メソッド（開発環境でのみ使用）
  testInsert() {
    const testContent = '【業務報告】\n\n■ 活動概要\n電話による相談対応を実施。緊急性の高い案件について関係者と連携を図った。\n\n■ 相談内容\n・急な体調変化に対する不安\n・夜間対応サービスの利用について\n\n■ 実施した対応\n・医療機関への連絡をサポート\n・緊急時対応マニュアルの説明\n\n■ 今後の対応\n定期的なフォローアップの実施予定'

    const textarea = document.getElementById('activity_content')
    if (textarea) {
      textarea.value = testContent
      textarea.dispatchEvent(new Event('input', { bubbles: true }))
    }
    this.statusTarget.textContent = '✅ テストデータを挿入しました'
    this.statusTarget.className = 'text-sm text-green-600 font-medium'
    
    setTimeout(() => {
      this.statusTarget.textContent = ''
      this.statusTarget.className = 'text-sm text-gray-600'
    }, 3000)
  }

  disconnect() {
    // no-op
  }
}