// SP用ドロワーコントローラー
// 左サイドバー（チャット履歴）と右パネル（タスク）をドロワーとして開閉する
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["leftDrawer", "rightDrawer", "backdrop"]

  connect() {
    // Escキーで閉じる
    this._onKeydown = (e) => { if (e.key === "Escape") this.closeAll() }
    document.addEventListener("keydown", this._onKeydown)

    // Turbo遷移前にドロワーを閉じる（SP画面でのオーバーレイ残留を防ぐ）
    this._onBeforeVisit = () => this.closeAll()
    document.addEventListener("turbo:before-visit", this._onBeforeVisit)

    // Turbo Frame更新前にドロワーを閉じる（SP画面でのオーバーレイ残留を防ぐ）
    this._onBeforeRender = () => this.closeAll()
    document.addEventListener("turbo:before-render", this._onBeforeRender)

    // ドロワー内のすべてのリンクにクリックイベントを追加
    this.addLinkListeners()
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
    document.removeEventListener("turbo:before-visit", this._onBeforeVisit)
    document.removeEventListener("turbo:before-render", this._onBeforeRender)
  }

  addLinkListeners() {
    // 左ドロワー内のリンク
    if (this.hasLeftDrawerTarget) {
      const leftLinks = this.leftDrawerTarget.querySelectorAll("a")
      leftLinks.forEach(link => {
        link.addEventListener("click", () => this.closeAll())
      })
    }

    // 右ドロワー内のリンク
    if (this.hasRightDrawerTarget) {
      const rightLinks = this.rightDrawerTarget.querySelectorAll("a")
      rightLinks.forEach(link => {
        link.addEventListener("click", () => this.closeAll())
      })
    }
  }

  openLeft() {
    this.leftDrawerTarget.classList.add("drawer-open")
    this.backdropTarget.classList.add("active")
    document.body.classList.add("overflow-hidden")
  }

  openRight() {
    this.rightDrawerTarget.classList.add("drawer-open")
    this.backdropTarget.classList.add("active")
    document.body.classList.add("overflow-hidden")
  }

  closeAll() {
    if (this.hasLeftDrawerTarget) {
      this.leftDrawerTarget.classList.remove("drawer-open")
    }
    if (this.hasRightDrawerTarget) {
      this.rightDrawerTarget.classList.remove("drawer-open")
    }
    if (this.hasBackdropTarget) {
      this.backdropTarget.classList.remove("active")
    }
    document.body.classList.remove("overflow-hidden")
  }
}
