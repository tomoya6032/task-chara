import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["installButton", "installSection", "iosInstructions"]
  
  connect() {
    console.log("PWA install controller connected")
    
    // Service Workerの登録
    this.registerServiceWorker()
    
    // 既にPWAとしてインストール済みか確認
    if (this.isStandalone()) {
      console.log("Already running as PWA")
      if (this.hasInstallSectionTarget) {
        this.installSectionTarget.style.display = "none"
      }
      return
    }
    
    // iOS判定
    this.isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream
    
    // Android Chrome等のインストールプロンプト対応
    window.addEventListener("beforeinstallprompt", (e) => {
      console.log("beforeinstallprompt event fired")
      e.preventDefault()
      this.deferredPrompt = e
      
      if (this.hasInstallButtonTarget) {
        this.installButtonTarget.disabled = false
      }
    })
    
    // インストール完了イベント
    window.addEventListener("appinstalled", () => {
      console.log("PWA installed successfully")
      this.deferredPrompt = null
      if (this.hasInstallSectionTarget) {
        this.installSectionTarget.style.display = "none"
      }
    })
  }
  
  // Service Workerの登録
  async registerServiceWorker() {
    if ("serviceWorker" in navigator) {
      try {
        const registration = await navigator.serviceWorker.register("/service-worker.js", {
          scope: "/"
        })
        
        console.log("Service Worker registered:", registration.scope)
        
        // 更新があるか確認（自動リロードは行わない）
        registration.addEventListener("updatefound", () => {
          console.log("Service Worker update found (no auto-reload)")
        })
      } catch (error) {
        console.error("Service Worker registration failed:", error)
      }
    }
  }
  
  // スタンドアロンモード（PWAとして起動）か判定
  isStandalone() {
    return window.matchMedia("(display-mode: standalone)").matches ||
           window.navigator.standalone === true
  }
  
  // インストールボタンクリック
  install() {
    console.log("Install button clicked")
    
    // iOSの場合は手順を表示
    if (this.isIOS) {
      this.showIOSInstructions()
      return
    }
    
    // Android Chrome等の場合はプロンプトを表示
    if (this.deferredPrompt) {
      this.deferredPrompt.prompt()
      
      this.deferredPrompt.userChoice.then((choiceResult) => {
        if (choiceResult.outcome === "accepted") {
          console.log("User accepted the install prompt")
        } else {
          console.log("User dismissed the install prompt")
        }
        this.deferredPrompt = null
      })
    } else {
      // プロンプトが利用できない場合（既にインストール済み、または対応していないブラウザ）
      alert("このブラウザではホーム画面への追加がサポートされていません。")
    }
  }
  
  // iOS用のインストール手順を表示
  showIOSInstructions() {
    if (this.hasIosInstructionsTarget) {
      this.iosInstructionsTarget.classList.remove("hidden")
    }
  }
  
  // iOS手順モーダルを閉じる
  closeIOSInstructions() {
    if (this.hasIosInstructionsTarget) {
      this.iosInstructionsTarget.classList.add("hidden")
    }
  }
}
