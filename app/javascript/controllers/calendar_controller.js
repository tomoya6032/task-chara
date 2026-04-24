import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    events: Array, 
    currentDate: String 
  }
  
  static targets = ["grid", "monthName"]

  connect() {
    this.currentDate = new Date(this.currentDateValue || new Date())
    this.events = this.eventsValue || []
    this.renderCalendar()
    this.updateMonthDisplay()
  }

  eventsValueChanged() {
    this.events = this.eventsValue
    this.renderCalendar()
  }

  currentDateValueChanged() {
    this.currentDate = new Date(this.currentDateValue)
    this.renderCalendar()
    this.updateMonthDisplay()
  }

  renderCalendar() {
    const grid = document.getElementById('calendar-grid')
    if (!grid) return

    grid.innerHTML = ''
    
    const year = this.currentDate.getFullYear()
    const month = this.currentDate.getMonth()
    
    // 月の最初の日と最後の日を取得
    const firstDay = new Date(year, month, 1)
    const lastDay = new Date(year, month + 1, 0)
    const firstDayOfWeek = firstDay.getDay() // 0=日曜日
    const daysInMonth = lastDay.getDate()
    
    // 前月の日付を追加（必要な場合）
    const prevMonth = new Date(year, month - 1, 0)
    const daysFromPrevMonth = firstDayOfWeek
    
    for (let i = daysFromPrevMonth; i > 0; i--) {
      const day = prevMonth.getDate() - i + 1
      const cell = this.createCalendarCell(day, true, new Date(year, month - 1, day))
      grid.appendChild(cell)
    }
    
    // 今月の日付を追加
    for (let day = 1; day <= daysInMonth; day++) {
      const date = new Date(year, month, day)
      const cell = this.createCalendarCell(day, false, date)
      grid.appendChild(cell)
    }
    
    // 次月の日付を追加（6週表示にするため）
    const totalCells = grid.children.length
    const remainingCells = 42 - totalCells // 6週 × 7日
    
    for (let day = 1; day <= remainingCells; day++) {
      const date = new Date(year, month + 1, day)
      const cell = this.createCalendarCell(day, true, date)
      grid.appendChild(cell)
    }
  }

  createCalendarCell(day, isOtherMonth, date) {
    const cell = document.createElement('div')
    cell.className = `calendar-cell ${isOtherMonth ? 'other-month' : ''}`
    
    // 今日かどうかチェック
    const today = new Date()
    if (date.toDateString() === today.toDateString()) {
      cell.classList.add('today')
    }
    
    // 日付番号
    const dateNumber = document.createElement('div')
    dateNumber.className = 'date-number text-sm font-medium'
    dateNumber.textContent = day
    cell.appendChild(dateNumber)
    
    // その日のイベントを追加
    const dayEvents = this.getEventsForDate(date)
    dayEvents.forEach(event => {
      const eventEl = this.createEventElement(event)
      cell.appendChild(eventEl)
    })
    
    // クリックイベント
    cell.addEventListener('click', () => {
      this.onCellClick(date)
    })
    
    return cell
  }

  createEventElement(event) {
    const eventEl = document.createElement('div')
    eventEl.className = `event-item event-${event.event_type}`
    eventEl.textContent = event.title
    eventEl.title = `${event.title}\n${this.formatTime(event.start_time)} - ${this.formatTime(event.end_time)}`
    
    // イベントクリックでモーダル表示
    eventEl.addEventListener('click', (e) => {
      e.stopPropagation()
      this.showEventDetails(event)
    })
    
    return eventEl
  }

  getEventsForDate(date) {
    return this.events.filter(event => {
      const eventDate = new Date(event.start_time)
      return eventDate.toDateString() === date.toDateString()
    }).sort((a, b) => new Date(a.start_time) - new Date(b.start_time))
  }

  formatTime(timeString) {
    const date = new Date(timeString)
    return date.toLocaleTimeString('ja-JP', { 
      hour: '2-digit', 
      minute: '2-digit',
      hour12: false 
    })
  }

  onCellClick(date) {
    // セルクリックで新しいイベント作成（日付を事前設定）
    const startInput = document.querySelector('input[name="event[start_time]"]')
    const endInput = document.querySelector('input[name="event[end_time]"]')
    
    if (startInput) {
      const startDateTime = new Date(date)
      startDateTime.setHours(9, 0) // デフォルトで午前9時
      startInput.value = this.formatDateTimeLocal(startDateTime)
    }
    
    if (endInput) {
      const endDateTime = new Date(date)
      endDateTime.setHours(10, 0) // デフォルトで1時間後
      endInput.value = this.formatDateTimeLocal(endDateTime)
    }
    
    this.openNewEventModal()
  }

  formatDateTimeLocal(date) {
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, '0')
    const day = String(date.getDate()).padStart(2, '0')
    const hours = String(date.getHours()).padStart(2, '0')
    const minutes = String(date.getMinutes()).padStart(2, '0')
    
    return `${year}-${month}-${day}T${hours}:${minutes}`
  }

  openNewEventModal() {
    const modal = document.getElementById('event-modal')
    if (modal) {
      modal.classList.remove('hidden')
    }
  }

  showEventDetails(event) {
    // イベント詳細モーダルを表示
    const eventDetails = `
      タイトル: ${event.title}
      開始: ${this.formatDateTime(event.start_time)}
      終了: ${this.formatDateTime(event.end_time)}
      種類: ${this.getEventTypeName(event.event_type)}
      ${event.description ? `詳細: ${event.description}` : ''}
    `
    
    alert(eventDetails) // 簡単な実装。後でモーダルに置き換え
  }

  formatDateTime(timeString) {
    const date = new Date(timeString)
    return date.toLocaleString('ja-JP', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    })
  }

  getEventTypeName(type) {
    const types = {
      'personal': '個人',
      'work': '仕事',
      'meeting': 'ミーティング',
      'task_deadline': 'タスク期限'
    }
    return types[type] || type
  }

  updateMonthDisplay() {
    const monthNames = ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月']
    const monthEl = document.getElementById('current-month')
    if (monthEl) {
      monthEl.textContent = `${this.currentDate.getFullYear()}年${monthNames[this.currentDate.getMonth()]}`
    }
  }

  // 月ナビゲーション
  navigateMonth(direction) {
    this.currentDate.setMonth(this.currentDate.getMonth() + direction)
    this.renderCalendar()
    this.updateMonthDisplay()
    
    // サーバーから新しい月のイベントを取得
    this.fetchEventsForMonth()
  }

  async fetchEventsForMonth() {
    try {
      const year = this.currentDate.getFullYear()
      const month = this.currentDate.getMonth() + 1
      
      const response = await fetch(`/calendar/events?year=${year}&month=${month}`, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const events = await response.json()
        this.eventsValue = events
      }
    } catch (error) {
      console.error('Failed to fetch events:', error)
    }
  }
}

// グローバル関数をStimulusコントローラーに接続
window.navigateMonth = function(direction) {
  const controller = document.querySelector('[data-controller="calendar"]')?.controller
  if (controller) {
    controller.navigateMonth(direction)
  }
}