class Event < ApplicationRecord
  # 関連
  belongs_to :character, optional: true

  # バリデーション
  validates :title, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :event_type, presence: true
  validate :event_type_must_be_valid
  validate :end_time_after_start_time

  # スコープ
  scope :for_date_range, ->(start_date, end_date) {
    where("start_time <= ? AND end_time >= ?", end_date.end_of_day, start_date.beginning_of_day)
  }
  scope :for_month, ->(year, month) {
    start_of_month = Date.new(year, month, 1).beginning_of_month
    end_of_month = Date.new(year, month, 1).end_of_month
    for_date_range(start_of_month, end_of_month)
  }
  scope :upcoming, -> { where("start_time >= ?", Time.current) }
  scope :past, -> { where("end_time < ?", Time.current) }
  scope :today, -> { for_date_range(Date.current, Date.current) }

  # Enum definitions (status only - event_type is now a flexible string)
  enum :status, {
    confirmed: 0,
    tentative: 1,
    cancelled: 2
  }

  # 色の設定（カスタムカテゴリ対応）
  def display_color
    # カスタムカテゴリの色を取得
    if event_type.to_s.start_with?("custom_") && character&.calendar_settings&.dig("custom_categories")
      custom_categories = character.calendar_settings["custom_categories"]
      if custom_categories.is_a?(Array)
        category = custom_categories.find { |cat| cat["id"] == event_type.to_s }
        return category["color"] if category&.dig("color")
      end
    end

    # 固定カテゴリの色
    case event_type.to_s
    when "personal"
      "#3B82F6"  # blue
    when "work"
      "#10B981"  # emerald
    when "meeting"
      "#F59E0B"  # amber
    when "task_deadline"
      "#EF4444"  # red
    when "google_sync"
      "#4285F4"  # google blue
    when "apple_sync"
      "#000000"  # black
    else
      "#6B7280"  # gray
    end
  end

  # カテゴリ名の取得（カスタムカテゴリ対応）
  def display_category_name
    # カスタムカテゴリの名前を取得
    if event_type.to_s.start_with?("custom_") && character&.calendar_settings&.dig("custom_categories")
      custom_categories = character.calendar_settings["custom_categories"]
      if custom_categories.is_a?(Array)
        category = custom_categories.find { |cat| cat["id"] == event_type.to_s }
        return category["name"] if category&.dig("name")
      end
    end

    # 固定カテゴリの名前
    case event_type.to_s
    when "personal"
      "個人"
    when "work"
      "仕事"
    when "meeting"
      "会議"
    when "task_deadline"
      "タスク期限"
    when "google_sync"
      "Google同期"
    when "apple_sync"
      "Apple同期"
    else
      event_type.to_s.humanize
    end
  end

  # 期間の計算
  def duration_in_minutes
    return 0 unless start_time && end_time
    ((end_time - start_time) / 1.minute).round
  end

  def all_day?
    start_time.beginning_of_day == start_time && end_time.end_of_day == end_time
  end

  # イベントタイプがタスク期限かどうかを判定
  def task_deadline?
    event_type == "task_deadline"
  end

  # タスクの期限をイベントとして作成
  def self.create_from_task(activity)
    return unless activity.deadline.present?

    create!(
      title: "📋 #{activity.title} (期限)",
      description: activity.description.present? ? activity.description.truncate(100) : nil,
      start_time: activity.deadline.beginning_of_day,
      end_time: activity.deadline.end_of_day,
      all_day: true,
      event_type: "task_deadline",
      external_id: "activity_#{activity.id}",
      character: activity.character
    )
  end

  # 外部カレンダーとの同期用
  def sync_to_google_calendar
    # Google Calendar APIとの同期処理
    # 後で実装
  end

  def sync_to_apple_calendar
    # Apple Calendar APIとの同期処理
    # 後で実装
  end

  private

  def end_time_after_start_time
    return unless start_time && end_time

    if end_time <= start_time
      errors.add(:end_time, "は開始時刻より後である必要があります")
    end
  end

  def event_type_must_be_valid
    allowed_fixed = %w[personal work meeting task_deadline google_sync apple_sync]
    # 固定値に含まれるか、または 'custom_' で始まればOK
    unless allowed_fixed.include?(event_type) || event_type&.start_with?("custom_")
      errors.add(:event_type, "は有効なイベントタイプではありません")
    end
  end
end
