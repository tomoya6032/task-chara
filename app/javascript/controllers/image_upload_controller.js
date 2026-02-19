// app/javascript/controllers/image_upload_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropzone", "fileInput", "urlInput", "preview", "previewImage"]

  connect() {
    this.setupDragAndDrop()
  }

  setupDragAndDrop() {
    this.dropzoneTarget.addEventListener('dragover', (e) => {
      e.preventDefault()
      this.dropzoneTarget.classList.add('border-blue-400', 'bg-blue-50')
    })

    this.dropzoneTarget.addEventListener('dragleave', (e) => {
      e.preventDefault()
      this.dropzoneTarget.classList.remove('border-blue-400', 'bg-blue-50')
    })

    this.dropzoneTarget.addEventListener('drop', (e) => {
      e.preventDefault()
      this.dropzoneTarget.classList.remove('border-blue-400', 'bg-blue-50')
      
      const files = e.dataTransfer.files
      if (files.length > 0) {
        this.handleFile(files[0])
      }
    })
  }

  triggerFileSelect() {
    this.fileInputTarget.click()
  }

  handleFileSelect(event) {
    const file = event.target.files[0]
    if (file) {
      this.handleFile(file)
    }
  }

  handleFile(file) {
    if (file.type.startsWith('image/')) {
      const reader = new FileReader()
      reader.onload = (e) => {
        this.showPreview(e.target.result)
        this.urlInputTarget.value = e.target.result
      }
      reader.readAsDataURL(file)
    }
  }

  handleUrlInput(event) {
    const url = event.target.value
    if (url && this.isValidImageUrl(url)) {
      this.showPreview(url)
    } else if (!url) {
      this.hidePreview()
    }
  }

  isValidImageUrl(url) {
    return /\.(jpg|jpeg|png|gif|webp)$/i.test(url) || url.startsWith('data:image/')
  }

  showPreview(src) {
    this.previewImageTarget.src = src
    this.previewTarget.classList.remove('hidden')
  }

  hidePreview() {
    this.previewTarget.classList.add('hidden')
    this.previewImageTarget.src = ''
  }

  clearImage() {
    this.urlInputTarget.value = ''
    this.fileInputTarget.value = ''
    this.hidePreview()
  }
}