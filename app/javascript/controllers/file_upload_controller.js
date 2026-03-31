import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values = { meetingId: String }
  static targets = [
    "content", "saveButton", "regenerateButton", 
    "voiceAnalysisButton", "imageAnalysisButton",
    "voiceInput", "voiceStatusContainer", "voiceFileName", "voiceFileSize", "voiceAnalysisButtonContainer",
    "imageInput", "imageStatusContainer", "imageFileName", "imageFileSize", "imageAnalysisButtonContainer"
  ]

  connect() {
    console.log('🔗 FileUploadController connected successfully!')
    console.log('Controller element:', this.element)
    console.log('Meeting ID value:', this.meetingIdValue)
    
    // WebSocketチャンネルをセットアップ
    this.setupWebSocket()
    
    // フォーム送信の制御を追加
    this.setupFormSubmitControl()
    
    // 解析中フラグを初期化
    this.isProcessing = false
    
    // ファイル選択状態を初期化
    this.selectedVoiceFile = null
    this.selectedImageFile = null
    
    // デバッグ用：必要な要素の存在確認
    this.debugCheckElements()
  }

  // デバッグ用：必要な要素の存在確認
  debugCheckElements() {
    console.log('🔍 Checking required DOM elements and Stimulus targets...')
    
    // DOM要素のチェック
    const requiredElements = [
      'meeting-voice-upload',
      'voice-file-status', 
      'voice-file-name',
      'voice-file-size',
      'voice-analysis-button',
      'voice-upload-label',
      'meeting-image-upload',
      'image-file-status',
      'image-file-name', 
      'image-file-size',
      'image-analysis-button',
      'ai-processing-status',
      'processing-message'
    ]
    
    let allFound = true
    requiredElements.forEach(id => {
      const element = document.getElementById(id)
      const exists = !!element
      console.log(`Element ${id}:`, exists ? '✅ EXISTS' : '❌ MISSING')
      if (!exists) allFound = false
    })
    
    // Stimulusターゲットのチェック
    console.log('🎯 Stimulus targets availability:')
    console.log('Voice targets:', {
      voiceInput: this.hasVoiceInputTarget,
      voiceStatusContainer: this.hasVoiceStatusContainerTarget,
      voiceFileName: this.hasVoiceFileNameTarget,
      voiceFileSize: this.hasVoiceFileSizeTarget,
      voiceAnalysisButtonContainer: this.hasVoiceAnalysisButtonContainerTarget,
      voiceAnalysisButton: this.hasVoiceAnalysisButtonTarget
    })
    
    console.log('Image targets:', {
      imageInput: this.hasImageInputTarget,
      imageStatusContainer: this.hasImageStatusContainerTarget,
      imageFileName: this.hasImageFileNameTarget,
      imageFileSize: this.hasImageFileSizeTarget,
      imageAnalysisButtonContainer: this.hasImageAnalysisButtonContainerTarget,
      imageAnalysisButton: this.hasImageAnalysisButtonTarget
    })
    
    console.log(`Overall DOM elements: ${allFound ? '✅ ALL FOUND' : '❌ SOME MISSING'}`)
    
    // File input event listener check
    const fileInput = document.getElementById('meeting-voice-upload')
    if (fileInput) {
      console.log('Voice file input data-action:', fileInput.getAttribute('data-action'))
    }
    
    const imageInput = document.getElementById('meeting-image-upload')
    if (imageInput) {
      console.log('Image file input data-action:', imageInput.getAttribute('data-action'))
    }
  }

  // フォーム送信制御をセットアップ
  setupFormSubmitControl() {
    const form = this.element.closest('form')
    if (form) {
      form.addEventListener('submit', (event) => {
        if (this.isProcessing) {
          event.preventDefault()
          event.stopPropagation()
          
          // 強力な視覚フィードバック
          this.showWarningPopup()
          this.shakeButtonAnimation()
          
          // 警告メッセージを表示
          this.showErrorStatus('⚠️ AI解析中のため保存できません。処理完了まで少々お待ちください。')
          
          // 保存ボタンを再度無効化（念のため）
          this.disableSaveButton()
          
          setTimeout(() => {
            this.hideAllStatus()
            this.showProcessingStatus('🤖 AI解析中...', '音声・画像からの議事録生成中です（通常60-90秒程度）')
          }, 3000)
          
          console.log('Form submission blocked: AI processing in progress')
          return false
        }
      })
    }
  }
  
  // ボタンを震わせるアニメーション
  shakeButtonAnimation() {
    const saveButton = document.getElementById('save-button')
    if (saveButton) {
      saveButton.classList.add('animate-pulse')
      saveButton.style.animation = 'shake 0.5s ease-in-out'
      setTimeout(() => {
        saveButton.classList.remove('animate-pulse')
        saveButton.style.animation = ''
      }, 1000)
    }
  }
  
  // 警告ポップアップ表示
  showWarningPopup() {
    const popup = document.createElement('div')
    popup.className = 'fixed top-4 right-4 bg-red-500 text-white px-6 py-3 rounded-lg shadow-lg z-50 animate-bounce'
    popup.innerHTML = '⚠️ AI解析中のため保存不可'
    document.body.appendChild(popup)
    
    setTimeout(() => {
      popup.remove()
    }, 3000)
  }

  // WebSocket接続をセットアップ
  setupWebSocket() {
    const meetingId = this.meetingIdValue || 'new'
    const sessionId = this.getSessionId()
    
    console.log('🔧 Setting up WebSocket connection:')
    console.log('- Meeting ID:', meetingId)
    console.log('- Session ID:', sessionId)
    
    // ActionCableの初期化確認
    const cable = consumer || window.App?.cable
    if (!cable) {
      console.warn('❌ ActionCable not available - WebSocket features disabled')
      return
    }
    
    console.log('✅ ActionCable consumer is available')
    
    if (meetingId !== 'new') {
      // 既存の議事録を編集中
      console.log('📝 Connecting to existing meeting WebSocket channel')
      this.channel = cable.subscriptions.create(
        { channel: "AiProcessingChannel", activity_id: meetingId },
        {
          received: (data) => this.handleWebSocketMessage(data),
          connected: () => console.log(`✅ WebSocket connected to meeting: ${meetingId}`),
          disconnected: () => console.log(`❌ WebSocket disconnected from meeting: ${meetingId}`)
        }
      )
      console.log('📡 Meeting WebSocket subscription created')
    } else {
      // 新規議事録作成中
      console.log('✨ Connecting to new meeting WebSocket channel')
      this.channel = cable.subscriptions.create(
        { channel: "AiProcessingChannel", session_id: sessionId },
        {
          received: (data) => {
            console.log('📨 WebSocket message received:', data)
            this.handleWebSocketMessage(data)
          },
          connected: () => {
            console.log(`✅ WebSocket connected to session: ${sessionId}`)
            console.log(`📡 Listening to channel: ai_processing_session_${sessionId}`)
          },
          disconnected: () => {
            console.log(`❌ WebSocket disconnected from session: ${sessionId}`)
            console.log(`📡 Disconnected from channel: ai_processing_session_${sessionId}`) 
          }
        }
      )
      console.log('📡 Session WebSocket subscription created')
    }
  }

  // セッションID取得（HTML data属性から）
  getSessionId() {
    // HTMLのdata-session-id属性から取得
    const sessionId = this.element.getAttribute('data-session-id')
    if (sessionId) {
      console.log(`Using Rails session ID: ${sessionId}`)
      return sessionId
    }
    
    // フォールバックとして独自生成（本来は使用されない）
    const userAgent = navigator.userAgent
    const timestamp = Date.now()
    const fallbackId = btoa(`${userAgent}_${timestamp}`).substring(0, 10)
    console.warn(`Fallback session ID generated: ${fallbackId}`)
    return fallbackId
  }

  // WebSocketメッセージを処理
  handleWebSocketMessage(data) {
    console.log('WebSocket message received:', data)
    
    if (data.type === 'meeting_voice_transcription') {
      if (data.status === 'completed') {
        this.isProcessing = false // 解析完了フラグを設定
        this.showSuccessStatus('🎉 音声からの議事録生成が完了しました')
        this.appendContentToTextarea(data.content)
        this.enableSaveButton()
        this.enableAnalysisButtons()
        // セッションストレージに保存（ページリロード時の復元用）
        sessionStorage.setItem('voice_transcription_content', data.content)
        
        // 完了時の詳細ログ
        console.log('Voice transcription completed successfully')
      } else if (data.status === 'error') {
        this.isProcessing = false // エラー時も処理フラグをクリア
        this.showErrorStatus(`音声解析エラー: ${data.error}`)
        this.enableSaveButton()
        this.enableAnalysisButtons()
      }
    } else if (data.type === 'meeting_image_ocr') {
      if (data.status === 'completed') {
        this.isProcessing = false // 解析完了フラグを設定
        this.showSuccessStatus('🎉 画像からの議事録生成が完了しました')
        this.appendContentToTextarea(data.content)
        this.enableSaveButton()
        this.enableAnalysisButtons()
        // セッションストレージに保存（ページリロード時の復元用）
        sessionStorage.setItem('image_ocr_content', data.content)
        
        // 完了時の詳細ログ
        console.log('Image OCR completed successfully')
      } else if (data.status === 'error') {
        this.isProcessing = false // エラー時も処理フラグをクリア
        this.showErrorStatus(`画像解析エラー: ${data.error}`)
        this.enableSaveButton()
        this.enableAnalysisButtons()
      }
    }
  }

// 音声ファイル選択処理（解析は開始しない）
  selectVoiceFile(event) {
    console.log('🎵 ===== Voice file selection started =====')
    console.log('Method called - selectVoiceFile is definitely firing')
    console.log('Event:', event)
    console.log('Event target:', event.target)
    console.log('Files array:', event.target.files)
    console.log('Files length:', event.target.files.length)
    
    const file = event.target.files[0]
    
    // 詳細なファイル情報をログ出力
    console.log('Selected file details:', {
      name: file?.name,
      type: file?.type,
      size: file?.size,
      lastModified: file?.lastModified
    })
    
    if (!file) {
      console.warn('❌ No file selected')
      this.clearVoiceFile()
      return
    }

    console.log('✅ File found, proceeding with validation...')

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
    
    console.log('🔍 Comprehensive file validation:', {
      fileName: file.name,
      mimeType: file.type || 'EMPTY/UNKNOWN',
      extension: fileExtension,
      isM4AFile: isM4AFile,
      isMimeTypeValid: isMimeTypeValid,
      isExtensionValid: isExtensionValid,
      finalValidation: isValidType
    })
    
    if (!isValidType) {
      console.error(`❌ File rejected - Type: ${file.type}, Extension: ${fileExtension}`)
      this.showErrorStatus(`❌ サポートされていないファイル形式です\n対応形式：MP3、WAV、M4A、WebM、AAC、OGG\n検出形式：${file.type || '不明'} (.${fileExtension})`)
      event.target.value = '' // ファイル選択をリセット
      return
    }
    
    // M4Aファイルは特別扱い - MIMEタイプが空でも処理続行
    if (isM4AFile) {
      console.log('🎵 M4A file confirmed - processing regardless of MIME type')
    }
    
    console.log(`✅ Audio file accepted: ${file.name}, type: ${file.type || 'unknown'}, size: ${(file.size/1024/1024).toFixed(2)}MB`)

    // ファイルサイズチェック（25MB制限）
    if (file.size > 25 * 1024 * 1024) {
      console.error(`File size too large: ${(file.size/1024/1024).toFixed(2)}MB`)
      this.showErrorStatus(`❌ 音声ファイルのサイズが大きすぎます（最大25MB）\n現在のサイズ：${(file.size/1024/1024).toFixed(2)}MB`)
      event.target.value = '' // ファイル選択をリセット
      return
    }
    
    // 選択されたファイルを保存
    this.selectedVoiceFile = file
    
    // UIを更新
    this.showVoiceFileSelected(file)
    this.hideAllStatus()
    
    console.log('✅ Voice file selected successfully, ready for analysis')
  }

  // 選択された音声ファイル情報を表示
  showVoiceFileSelected(file) {
    console.log('🎯 showVoiceFileSelected called with file:', file.name)
    
    // Stimulusターゲットの存在確認
    console.log('Stimulus targets availability:', {
      voiceStatusContainer: this.hasVoiceStatusContainerTarget,
      voiceFileName: this.hasVoiceFileNameTarget, 
      voiceFileSize: this.hasVoiceFileSizeTarget,
      voiceAnalysisButtonContainer: this.hasVoiceAnalysisButtonContainerTarget
    })
    
    // Stimulusターゲット参照を使用（ID参照ではなく）
    if (this.hasVoiceStatusContainerTarget && this.hasVoiceFileNameTarget && 
        this.hasVoiceFileSizeTarget && this.hasVoiceAnalysisButtonContainerTarget) {
      
      // ファイル情報を設定
      this.voiceFileNameTarget.textContent = file.name
      this.voiceFileSizeTarget.textContent = `(${(file.size/1024/1024).toFixed(2)}MB)`
      
      console.log('✅ File info set via Stimulus targets:', {
        name: file.name,
        size: `(${(file.size/1024/1024).toFixed(2)}MB)`
      })
      
      // UI要素を表示
      this.voiceStatusContainerTarget.classList.remove('hidden')
      this.voiceAnalysisButtonContainerTarget.classList.remove('hidden')
      
      console.log('✅ File status and button made visible via Stimulus targets')
      
      // ファイル形式に応じたアニメーション
      const fileExtension = file.name.split('.').pop().toLowerCase()
      if (fileExtension === 'm4a') {
        this.voiceStatusContainerTarget.classList.add('animate-pulse')
        setTimeout(() => this.voiceStatusContainerTarget.classList.remove('animate-pulse'), 1000)
        console.log('🎵 M4A animation applied via Stimulus target')
      }
    } else {
      console.error('❌ Some Stimulus targets not available for voice file display:', {
        voiceStatusContainer: this.hasVoiceStatusContainerTarget,
        voiceFileName: this.hasVoiceFileNameTarget,
        voiceFileSize: this.hasVoiceFileSizeTarget, 
        voiceAnalysisButtonContainer: this.hasVoiceAnalysisButtonContainerTarget
      })
      
      console.error('❌ Cannot display voice file info - required Stimulus targets not found')
    }
  }

  // 音声ファイル選択をクリア
  clearVoiceFile() {
    console.log('🗑️  Clearing voice file selection')
    
    this.selectedVoiceFile = null
    
    // Stimulusターゲット参照を優先使用
    if (this.hasVoiceInputTarget) {
      this.voiceInputTarget.value = ''
      console.log('✅ Voice input cleared via Stimulus target')
    }
    
    if (this.hasVoiceStatusContainerTarget) {
      this.voiceStatusContainerTarget.classList.add('hidden')
      console.log('✅ Voice status hidden via Stimulus target')
    }
    
    if (this.hasVoiceAnalysisButtonContainerTarget) {
      this.voiceAnalysisButtonContainerTarget.classList.add('hidden')
      console.log('✅ Voice analysis button hidden via Stimulus target')
    }
    
    console.log('✅ Voice file selection cleared')
  }

  // 音声解析を開始
  startVoiceAnalysis() {
    if (!this.selectedVoiceFile) {
      this.showErrorStatus('❌ 音声ファイルが選択されていません')
      return
    }

    if (this.isProcessing) {
      this.showErrorStatus('既に解析処理が実行中です。完了までお待ちください。')
      return
    }

    console.log('🚀 Starting voice analysis process...')
    
    const file = this.selectedVoiceFile
    const fileExtension = file.name.split('.').pop().toLowerCase()
    
    // 解析開始フラグを設定
    this.isProcessing = true
    
    // M4Aファイル特有の警告表示
    if (fileExtension === 'm4a') {
      console.log('🎵 M4A file detected - applying optimized processing')
      this.showProcessingStatus('🎵 M4Aファイルを解析中...', 'iPhone等で録音されたM4Aファイルを処理中です（30-90秒程度）')
    } else {
      console.log(`🔊 ${fileExtension.toUpperCase()} file detected`)
      this.showProcessingStatus('🔊 音声ファイルを解析中...', 'AI解析には時間がかかります（通常30-60秒程度）')
    }
    
    this.updateProgress(15)
    this.disableSaveButton()
    this.disableAnalysisButtons()

    const formData = new FormData()
    formData.append('voice_file', file)
    
    // プロンプトテンプレートIDを取得してFormDataに追加
    const promptTemplateSelect = document.querySelector('select[name="meeting_minute[prompt_template_id]"]')
    if (promptTemplateSelect && promptTemplateSelect.value) {
      formData.append('prompt_template_id', promptTemplateSelect.value)
      console.log(`📝 Using prompt template ID: ${promptTemplateSelect.value}`)
    } else {
      console.log('📝 No prompt template selected, using default')
    }
    
    // デバッグ用：FormDataの内容確認
    console.log('FormData contents:')
    for (let [key, value] of formData.entries()) {
      if (value instanceof File) {
        console.log(`  ${key}: File(${value.name}, ${value.type}, ${value.size} bytes)`)
      } else {
        console.log(`  ${key}: ${value}`)
      }
    }
    
    // 新規作成か編集かで分岐
    const meetingId = this.meetingIdValue
    let uploadUrl
    
    if (meetingId === 'new' || !meetingId) {
      const sessionId = this.getSessionId()
      uploadUrl = '/meeting_minutes/process_voice_transcription_new'
      formData.append('session_id', sessionId)
      console.log(`📤 Starting voice analysis for new meeting, session_id: ${sessionId}`)
    } else {
      formData.append('meeting_id', meetingId)
      uploadUrl = `/meeting_minutes/${meetingId}/process_voice_transcription`
      console.log(`📤 Starting voice analysis for existing meeting: ${meetingId}`)
    }
    
    console.log(`📡 Upload URL: ${uploadUrl}`)
    this.uploadFile(uploadUrl, formData, 'voice')
  }

  // 画像ファイル選択処理（解析は開始しない）
  selectImageFile(event) {
    console.log('🖼️ ===== Image file selection started =====')
    console.log('Method called - selectImageFile is definitely firing')
    
    const file = event.target.files[0]
    if (!file) {
      this.clearImageFile()
      return
    }

    // ファイル形式チェック
    const allowedTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/jpg']
    const allowedExtensions = ['jpg', 'jpeg', 'png', 'webp']
    const fileExtension = file.name.split('.').pop().toLowerCase()
    
    const isValidType = allowedTypes.includes(file.type) || allowedExtensions.includes(fileExtension)
    
    if (!isValidType) {
      this.showErrorStatus('❌ サポートされていない画像ファイル形式です（JPEG、PNG、WebPが利用できます）')
      event.target.value = ''
      return
    }

    // ファイルサイズチェック（20MB制限）
    if (file.size > 20 * 1024 * 1024) {
      this.showErrorStatus(`❌ 画像ファイルのサイズが大きすぎます（最大20MB）\n現在のサイズ：${(file.size/1024/1024).toFixed(2)}MB`)
      event.target.value = ''
      return
    }

    // 選択されたファイルを保存
    this.selectedImageFile = file
    
    // UIを更新
    this.showImageFileSelected(file)
    this.hideAllStatus()
    
    console.log('✅ Image file selected successfully, ready for analysis')
  }

  // 選択された画像ファイル情報を表示
  showImageFileSelected(file) {
    console.log('🖼️ showImageFileSelected called with file:', file.name)
    
    // Stimulusターゲット参照を使用
    if (this.hasImageStatusContainerTarget && this.hasImageFileNameTarget && 
        this.hasImageFileSizeTarget && this.hasImageAnalysisButtonContainerTarget) {
      
      this.imageFileNameTarget.textContent = file.name
      this.imageFileSizeTarget.textContent = `(${(file.size/1024/1024).toFixed(2)}MB)`
      
      this.imageStatusContainerTarget.classList.remove('hidden')
      this.imageAnalysisButtonContainerTarget.classList.remove('hidden')
      
      console.log('✅ Image file status updated via Stimulus targets')
    } else {
      console.error('❌ Image Stimulus targets not available - using fallback')
      // フォールバック処理
      const statusContainer = document.getElementById('image-file-status')
      const nameElement = document.getElementById('image-file-name')
      const sizeElement = document.getElementById('image-file-size')
      const analysisButton = document.getElementById('image-analysis-button')
      
      if (statusContainer && nameElement && sizeElement && analysisButton) {
        nameElement.textContent = file.name
        sizeElement.textContent = `(${(file.size/1024/1024).toFixed(2)}MB)`
        statusContainer.classList.remove('hidden')
        analysisButton.classList.remove('hidden')
      }
    }
  }

  // 画像ファイル選択をクリア
  clearImageFile() {
    console.log('🗑️  Clearing image file selection')
    
    this.selectedImageFile = null
    
    // Stimulusターゲット参照を優先使用
    if (this.hasImageInputTarget) {
      this.imageInputTarget.value = ''
    }
    
    if (this.hasImageStatusContainerTarget) {
      this.imageStatusContainerTarget.classList.add('hidden')
    }
    
    if (this.hasImageAnalysisButtonContainerTarget) {
      this.imageAnalysisButtonContainerTarget.classList.add('hidden')
    }
    
    console.log('✅ Image file selection cleared')
  }

  // 画像解析を開始
  startImageAnalysis() {
    if (!this.selectedImageFile) {
      this.showErrorStatus('❌ 画像ファイルが選択されていません')
      return
    }

    if (this.isProcessing) {
      this.showErrorStatus('既に解析処理が実行中です。完了までお待ちください。')
      return
    }

    console.log('🚀 Starting image analysis process...')
    
    const file = this.selectedImageFile
    
    // 解析開始フラグを設定
    this.isProcessing = true
    
    this.showProcessingStatus('🖼️ 画像ファイルを解析中...', 'AI解析には時間がかかります（通常30-60秒程度）')
    this.updateProgress(10)
    this.disableSaveButton()
    this.disableAnalysisButtons()

    const formData = new FormData()
    formData.append('image_file', file)
    
    // プロンプトテンプレートIDを取得してFormDataに追加
    const promptTemplateSelect = document.querySelector('select[name="meeting_minute[prompt_template_id]"]')
    if (promptTemplateSelect && promptTemplateSelect.value) {
      formData.append('prompt_template_id', promptTemplateSelect.value)
      console.log(`📝 Using prompt template ID: ${promptTemplateSelect.value}`)
    } else {
      console.log('📝 No prompt template selected, using default')
    }
    
    // 新規作成か編集かで分岐
    const meetingId = this.meetingIdValue
    let uploadUrl
    
    if (meetingId === 'new' || !meetingId) {
      const sessionId = this.getSessionId()
      uploadUrl = '/meeting_minutes/process_image_ocr_new'
      formData.append('session_id', sessionId)
      console.log(`📤 Starting image analysis for new meeting, session_id: ${sessionId}`)
    } else {
      formData.append('meeting_id', meetingId)
      uploadUrl = `/meeting_minutes/${meetingId}/process_image_ocr`
      console.log(`📤 Starting image analysis for existing meeting: ${meetingId}`)
    }

    this.uploadFile(uploadUrl, formData, 'image')
  }

  // ファイル選択状況表示
  // 処理状況表示
  showProcessingStatus(message, detailMessage = '') {
    this.hideAllStatus()
    
    // pending status を削除
    this.clearPendingStatus()
    
    const statusElement = document.getElementById('ai-processing-status')
    const messageElement = document.getElementById('processing-message')
    const detailElement = document.getElementById('detailed-status')
    const progressContainer = document.getElementById('progress-container')
    
    if (statusElement && messageElement) {
      statusElement.classList.remove('hidden')
      messageElement.textContent = message
      
      if (detailElement && detailMessage) {
        detailElement.textContent = detailMessage
      }
      
      if (progressContainer) {
        progressContainer.classList.remove('hidden')
      }
      
      // ステータス表示時にパルス効果を追加
      statusElement.classList.add('animate-pulse')
      setTimeout(() => {
        statusElement.classList.remove('animate-pulse')
      }, 2000)
    }
  }
  
  // pending status をクリア
  clearPendingStatus() {
    const pendingElements = document.querySelectorAll('[id$="-pending-status"]')
    pendingElements.forEach(element => {
      if (element && element.parentNode) {
        element.remove()
      }
    })
  }

  // 保存ボタンを無効化
  disableSaveButton() {
    const saveButton = document.getElementById('save-button')
    if (saveButton) {
      saveButton.disabled = true
      saveButton.innerHTML = '<span class="inline-flex items-center"><div class="animate-spin rounded-full h-4 w-4 border-2 border-white border-t-transparent mr-2"></div>🤖 AI解析中...</span>'
      saveButton.classList.add('opacity-75', 'cursor-not-allowed', 'bg-gray-500')
      saveButton.classList.remove('bg-blue-600', 'hover:bg-blue-700')
      console.log('Save button disabled during AI processing')
    }
    
    // Stimulusターゲット経由でもボタンを無効化
    if (this.hasSaveButtonTarget) {
      this.saveButtonTarget.disabled = true
      this.saveButtonTarget.innerHTML = '<span class="inline-flex items-center"><div class="animate-spin rounded-full h-4 w-4 border-2 border-white border-t-transparent mr-2"></div>🤖 AI解析中...</span>'
      this.saveButtonTarget.classList.add('opacity-75', 'cursor-not-allowed', 'bg-gray-500')
      this.saveButtonTarget.classList.remove('bg-blue-600', 'hover:bg-blue-700')
    }
    
    // AI再生成ボタンも無効化 (Stimulusターゲット使用またはクラス検索)
    if (this.hasRegenerateButtonTarget) {
      this.regenerateButtonTarget.disabled = true
      this.regenerateButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
    } else {
      // フォールバック: テキスト内容で検索
      const buttons = document.querySelectorAll('button[type="submit"]')
      const regenerateButton = Array.from(buttons).find(btn => btn.textContent.includes('🤖'))
      if (regenerateButton) {
        regenerateButton.disabled = true
        regenerateButton.classList.add('opacity-50', 'cursor-not-allowed')
      }
    }
  }

  // 保存ボタンを有効化
  enableSaveButton() {
    const saveButton = document.getElementById('save-button')
    if (saveButton) {
      saveButton.disabled = false
      saveButton.innerHTML = '💾 議事録を作成'
      saveButton.classList.remove('opacity-75', 'cursor-not-allowed', 'bg-gray-500')
      saveButton.classList.add('bg-blue-600', 'hover:bg-blue-700')
      console.log('Save button enabled after AI processing')
    }
    
    // Stimulusターゲット経由でもボタンを有効化
    if (this.hasSaveButtonTarget) {
      this.saveButtonTarget.disabled = false
      this.saveButtonTarget.innerHTML = '💾 議事録を作成'
      this.saveButtonTarget.classList.remove('opacity-75', 'cursor-not-allowed', 'bg-gray-500')
      this.saveButtonTarget.classList.add('bg-blue-600', 'hover:bg-blue-700')
    }
    
    // AI再生成ボタンも有効化 (Stimulusターゲット使用またはクラス検索)
    if (this.hasRegenerateButtonTarget) {
      this.regenerateButtonTarget.disabled = false
      this.regenerateButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
    } else {
      // フォールバック: テキスト内容で検索
      const buttons = document.querySelectorAll('button[type="submit"]')
      const regenerateButton = Array.from(buttons).find(btn => btn.textContent.includes('🤖'))
      if (regenerateButton) {
        regenerateButton.disabled = false
        regenerateButton.classList.remove('opacity-50', 'cursor-not-allowed')
      }
    }
  }

  // 解析ボタンを無効化
  disableAnalysisButtons() {
    console.log('🚫 Disabling analysis buttons')
    
    // Stimulusターゲット参照を優先使用
    if (this.hasVoiceAnalysisButtonTarget) {
      this.voiceAnalysisButtonTarget.disabled = true
      console.log('✅ Voice analysis button disabled via Stimulus target')
    }
    if (this.hasImageAnalysisButtonTarget) {
      this.imageAnalysisButtonTarget.disabled = true
      console.log('✅ Image analysis button disabled via Stimulus target')
    }
    
    // フォールバック：IDで検索
    const voiceButton = document.getElementById('voice-analysis-button')?.querySelector('button')
    const imageButton = document.getElementById('image-analysis-button')?.querySelector('button')
    
    if (voiceButton) {
      voiceButton.disabled = true
      console.log('⚠️ Voice button disabled via ID fallback')
    }
    if (imageButton) {
      imageButton.disabled = true
      console.log('⚠️ Image button disabled via ID fallback')
    }
    
    console.log('🚫 Analysis buttons disabled during processing')
  }

  // 解析ボタンを有効化
  enableAnalysisButtons() {
    console.log('✅ Enabling analysis buttons')
    
    // Stimulusターゲット参照を優先使用
    if (this.hasVoiceAnalysisButtonTarget) {
      this.voiceAnalysisButtonTarget.disabled = false
      console.log('✅ Voice analysis button enabled via Stimulus target')
    }
    if (this.hasImageAnalysisButtonTarget) {
      this.imageAnalysisButtonTarget.disabled = false
      console.log('✅ Image analysis button enabled via Stimulus target')
    }
    
    // フォールバック：IDで検索
    const voiceButton = document.getElementById('voice-analysis-button')?.querySelector('button')
    const imageButton = document.getElementById('image-analysis-button')?.querySelector('button')
    
    if (voiceButton) {
      voiceButton.disabled = false
      console.log('⚠️ Voice button enabled via ID fallback')
    }
    if (imageButton) {
      imageButton.disabled = false
      console.log('⚠️ Image button enabled via ID fallback')
    }
    
    console.log('✅ Analysis buttons enabled after processing')
  }

  // 成功メッセージ表示
  showSuccessStatus(message) {
    this.hideAllStatus()
    this.clearPendingStatus()
    
    const statusElement = document.getElementById('upload-success-status')
    const messageElement = document.getElementById('success-message')
    
    if (statusElement && messageElement) {
      messageElement.textContent = message
      statusElement.classList.remove('hidden')
      
      // 成功時のセレブレーション効果
      statusElement.classList.add('animate-bounce')
      setTimeout(() => {
        statusElement.classList.remove('animate-bounce')
      }, 2000)
    }
    
    this.updateProgress(100)
    
    // ファイル選択ボタンをリセット
    this.resetUploadButtons()
    
    setTimeout(() => this.hideAllStatus(), 5000)
  }

  // エラーメッセージ表示
  showErrorStatus(message) {
    this.hideAllStatus()
    this.clearPendingStatus()
    
    const statusElement = document.getElementById('upload-error-status')
    const messageElement = document.getElementById('error-message')
    
    if (statusElement && messageElement) {
      messageElement.textContent = message
      statusElement.classList.remove('hidden')
      
      // エラー時のシェイク効果
      statusElement.classList.add('animate-pulse')
      setTimeout(() => {
        statusElement.classList.remove('animate-pulse')
      }, 3000)
    }

    this.updateProgress(0)
    
    // エラー時は確実に処理フラグをクリアし、保存ボタンを有効化
    this.isProcessing = false
    this.enableSaveButton()
    
    // ファイル選択ボタンをリセット
    this.resetUploadButtons()
    
    setTimeout(() => this.hideAllStatus(), 10000)
  }
  
  // アップロードボタンをリセット
  resetUploadButtons() {
    ['voice', 'image'].forEach(type => {
      const label = document.getElementById(`${type}-upload-label`)
      const statusElement = document.getElementById(`${type}-file-status`)
      
      if (label) {
        const icon = type === 'voice' ? '🎤' : '📷'
        label.innerHTML = `${icon} ${type === 'voice' ? '音声' : '画像'}ファイル選択`
        label.classList.remove('bg-gray-500', 'hover:bg-gray-600', 'text-xs')
        label.classList.add(`bg-${type === 'voice' ? 'green' : 'purple'}-600`, `hover:bg-${type === 'voice' ? 'green' : 'purple'}-700`)
      }
      
      if (statusElement) {
        statusElement.classList.add('hidden')
      }
      
      // ファイル input をリセット
      const fileInput = document.getElementById(`meeting-${type}-upload`)
      if (fileInput) {
        fileInput.value = ''
      }
    })
  }

  // プログレスバー更新
  updateProgress(percentage) {
    const progressBar = document.getElementById('progress-bar')
    if (progressBar) {
      progressBar.style.width = `${percentage}%`
    }
  }

  // 全ての状況表示を非表示
  hideAllStatus() {
    const statusIds = ['ai-processing-status', 'upload-error-status', 'upload-success-status']
    statusIds.forEach(id => {
      const element = document.getElementById(id)
      if (element) {
        element.classList.add('hidden')
      }
    })
  }

  // ファイル名短縮
  truncateFilename(filename, maxLength = 20) {
    if (filename.length <= maxLength) return filename
    const extension = filename.split('.').pop()
    const name = filename.substring(0, filename.lastIndexOf('.'))
    const truncated = name.substring(0, maxLength - extension.length - 4) + '...'
    return `${truncated}.${extension}`
  }

  // ファイルアップロード実行
  async uploadFile(url, formData, type) {
    try {
      // アップロード開始の詳細表示
      this.updateProgress(20)
      this.showProcessingStatus(`🚀 ${type === 'voice' ? '音声' : '画像'}ファイルをサーバーにアップロード中...`, 'ファイルの送信を開始しています')

      const response = await fetch(url, {
        method: 'POST',
        body: formData,
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      this.updateProgress(60)
      this.showProcessingStatus('📤 アップロード完了、AI解析開始...', 'サーバーで処理を開始しています')

      if (!response.ok) {
        throw new Error(`サーバーエラー: ${response.status}`)
      }

      const result = await response.json()
      
      if (result.status === 'processing') {
        this.updateProgress(80)
        this.showProcessingStatus('🤖 AI解析中...', '議事録を生成しています。WebSocketから結果を待機中...')
        console.log(`Upload initiated, waiting for WebSocket response...`)
        
        // WebSocketからの結果を待つ（uploadFileはここで完了し、handleWebSocketMessageで結果を処理）
        
      } else if (result.status === 'success') {
        // 直接成功レスポンスが返った場合（稀なケース）
        this.updateProgress(100)
        this.isProcessing = false // 成功時も処理フラグをクリア
        this.showSuccessStatus(`${type === 'voice' ? '音声' : '画像'}からの議事録生成が完了しました`)
        this.appendContentToTextarea(result.content || result.message)
        this.enableSaveButton()
      } else {
        this.isProcessing = false // 失敗時も処理フラグをクリア
        throw new Error(result.message || 'アップロードに失敗しました')
      }

    } catch (error) {
      console.error('Upload error:', error)
      this.isProcessing = false // エラー時も解析中フラグをクリア
      this.enableSaveButton() // エラー時も保存ボタンを有効化
      
      if (error.name === 'AbortError') {
        this.showErrorStatus('アップロードがキャンセルされました')
      } else if (error.message.includes('ネットワーク')) {
        this.showErrorStatus('ネットワークエラーが発生しました。接続を確認してください。')
      } else if (error.message.includes('タイムアウト')) {
        this.showErrorStatus('アップロードがタイムアウトしました。ファイルサイズが大きすぎる可能性があります。')
      } else {
        this.showErrorStatus(`アップロードエラー: ${error.message}`)
      }
    }
  }

  // テキストエリアに内容を追加
  appendContentToTextarea(content) {
    // 複数の方法でテキストエリアを見つける
    let textarea = document.querySelector('textarea[name*="content"]') ||
                   document.querySelector('textarea[name="meeting_minute[content]"]') ||
                   document.getElementById('meeting_minute_content') ||
                   document.querySelector('#content')
                   
    if (textarea && content) {
      const currentContent = textarea.value
      const separator = '\n\n--- AI生成内容 ---\n'
      const newContent = currentContent ? 
        `${currentContent}${separator}${content}` : 
        content
      
      textarea.value = newContent
      
      // テキストエリアにフォーカスして最下部にスクロール
      textarea.focus()
      textarea.scrollTop = textarea.scrollHeight
      
      // 変更イベントを発火（必要に応じて）
      textarea.dispatchEvent(new Event('input', { bubbles: true }))
      
      console.log('Content appended to textarea successfully')
    } else {
      console.error('Textarea not found or content is empty')
      console.log('Available textareas:', document.querySelectorAll('textarea'))
    }
  }
}