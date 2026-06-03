// SP用ドロワーコントローラー
// 左サイドバー（チャット履歴）と右パネル（タスク）をドロワーとして開閉する
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["leftDrawer", "rightDrawer", "backdrop"]

  connect() {
    // Escキーで閉じる
    this._onKeydown = (e) => { if (e.key === "Escape") this.closeAll() }
    document.addEventListener("keydown", this._onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
  }

  openLeft() {
    this.leftDrawerTarget.classList.add("drawer-open")
    this.backdropTarget.style.display = "block"
    document.body.classList.add("overflow-hidden")
  }

  openRight() {
    this.rightDrawerTarget.classList.add("drawer-open")
    this.backdropTarget.style.display = "block"
    document.body.classList.add("overflow-hidden")
  }

  closeAll() {
    this.leftDrawerTarget.classList.remove("drawer-open")
    this.rightDrawerTarget.classList.remove("drawer-open")
    this.backdropTarget.style.display = "none"
    document.body.classList.remove("overflow-hidden")
  }
}
