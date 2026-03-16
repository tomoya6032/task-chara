// app/javascript/controllers/voice_recorder_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["startButton", "stopButton", "status", "audio", "cancelButton"]
  static values = { activityId: Number }

  connect() {
    console.log("Voice recorder controller connected")
    this.mediaRecorder = null
    this.audioChunks = []
    this.isProcessing = false
  }

  async startRecording() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ 
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        } 
      })
      
      this.mediaRecorder = new MediaRecorder(stream, {
        mimeType: 'audio/webm;codecs=opus'
      })
      
      this.audioChunks = []
      
      this.mediaRecorder.ondataavailable = (event) => {
        this.audioChunks.push(event.data)
      }
      
      this.mediaRecorder.onstop = () => {
        this.processRecording()
      }
      
      this.mediaRecorder.start()
      
      // UI更新
      this.startButtonTarget.style.display = 'none'
      this.stopButtonTarget.style.display = 'inline-flex'
      this.statusTarget.textContent = '🎙️ 録音中...'
      this.statusTarget.className = 'text-sm text-red-600 font-medium'
      
    } catch (error) {
      console.error('マイクアクセスエラー:', error)
      this.statusTarget.textContent = 'マイクにアクセスできません'
      this.statusTarget.className = 'text-sm text-red-600'
    }
  }

  stopRecording() {
    if (this.mediaRecorder && this.mediaRecorder.state === 'recording') {
      this.mediaRecorder.stop()
      
      // マイクストリームを停止
      this.mediaRecorder.stream.getTracks().forEach(track => track.stop())
      
      // UI更新
      this.startButtonTarget.style.display = 'inline-flex'
      this.stopButtonTarget.style.display = 'none'
      this.statusTarget.textContent = '⏳ 処理中...'
      this.statusTarget.className = 'text-sm text-blue-600 font-medium'
    }
  }

  async processRecording() {
    if (this.isProcessing) return
    
    this.isProcessing = true
    const audioBlob = new Blob(this.audioChunks, { type: 'audio/webm;codecs=opus' })
    
    // 音声プレビューを作成
    const audioUrl = URL.createObjectURL(audioBlob)
    if (this.hasAudioTarget) {
      this.audioTarget.src = audioUrl
      this.audioTarget.style.display = 'block'
    }
    
    // キャンセルボタンを表示
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.style.display = 'inline-flex'
    }
    
    // サーバーに送信
    const formData = new FormData()
    formData.append('audio_file', audioBlob, 'recording.webm')
    
    try {
      const response = await fetch(`/activities/${this.activityIdValue}/process_voice_transcription`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      const result = await response.json()
      
      if (result.status === 'processing') {
        this.statusTarget.textContent = '🤖 ' + result.message
        this.statusTarget.className = 'text-sm text-blue-600 font-medium'
        
        // WebSocketで結果を待機
        this.subscribeToVoiceResults()
      } else {
        throw new Error(result.message)
      }
      
    } catch (error) {
      console.error('音声送信エラー:', error)
      this.showError('エラーが発生しました: ' + error.message)
      this.resetProcessingState()
    }
  }

  cancelProcessing() {
    if (!this.isProcessing) return
    
    console.log('Voice processing cancelled by user')
    this.showError('処理をキャンセルしました')
    this.resetProcessingState()
  }

  resetProcessingState() {
    this.isProcessing = false
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.style.display = 'none'
    }
  }

  showError(message) {
    this.statusTarget.textContent = '❌ ' + message
    this.statusTarget.className = 'text-sm text-red-600'
  }

  subscribeToVoiceResults() {
    // WebSocketの結果はwebsocket-controllerで処理される
    // このメソッドは呼ばれなくなる予定だが、念のため維持
    console.log("Voice processing started, waiting for WebSocket result...")
  }
}