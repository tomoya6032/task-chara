require "ice_cube"

class Event < ApplicationRecord
  # 仮想属性（繰り返しインスタンスの識別用）
  attr_accessor :is_virtual_occurrence, :occurrence_start_time

  # 通知タイミング定数（分単位）
  REMINDER_OPTIONS = {
    "通知なし"  => nil,
    "30分前"   => 30,
    "1時間前"  => 60,
    "3時間前"  => 180,
    "1日前"    => 1440,
    "3日前"    => 4320
  }.freeze

  # 関連
  belongs_to :character, optional: true
  belongs_to :user, optional: true
  belongs_to :recurring_event, class_name: "Event", optional: true
  has_many :recurring_instances, class_name: "Event", foreign_key: "recurring_event_id", dependent: :destroy

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
  scope :recurring_parents, -> { where(recurring: true, recurring_event_id: nil) }
  scope :non_recurring, -> { where(recurring: false) }

  # 論理削除関連スコープ
  scope :active, -> { where(cancelled_at: nil) }
  scope :soft_deleted, -> { where.not(cancelled_at: nil) }
  scope :exceptions, -> { where(is_exception: true) }

  # Enum definitions (status only - event_type is now a flexible string)
  enum :status, {
    confirmed: 0,
    tentative: 1,
    cancelled: 2
  }

  # reminder_minutes が変更されたらリマインド送信済みフラグをリセット
  before_save :reset_reminder_sent_flag, if: :reminder_minutes_changed?

  # 色の設定（カスタムカテゴリ対応）
  def display_color
    settings = character&.calendar_settings_hash || {}

    # カスタムカテゴリの色を取得
    if event_type.to_s.start_with?("custom_") && settings["custom_categories"].present?
      custom_categories = settings["custom_categories"]
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
    settings = character&.calendar_settings_hash || {}

    # カスタムカテゴリの名前を取得
    if event_type.to_s.start_with?("custom_") && settings["custom_categories"].present?
      custom_categories = settings["custom_categories"]
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
    # DISABLED: Activity.deadline does not exist
    # この機能はTaskモデルに移行する必要があります
    return
    
    # return unless activity.deadline.present?
    #
    # create!(
    #   title: "📋 #{activity.title} (期限)",
    #   description: activity.description.present? ? activity.description.truncate(100) : nil,
    #   start_time: activity.deadline.beginning_of_day,
    #   end_time: activity.deadline.end_of_day,
    #   all_day: true,
    #   event_type: "task_deadline",
    #   external_id: "activity_#{activity.id}",
    #   character: activity.character
    # )
  end

  # 外部カレンダーとの同期用
  def sync_to_google_calendar
    # Google Calendar APIとの同期処理
    # 後で実装
  end

  # === 論理削除・例外処理メソッド ===

  # 論理削除（カレンダーから非表示にするが、データは残す）
  def soft_delete!
    update!(cancelled_at: Time.current)
  end

  # 論理削除を取り消して復元
  def restore!
    update!(cancelled_at: nil)
  end

  # 削除済みかどうか
  def cancelled?
    cancelled_at.present?
  end

  # 有効なイベントかどうか
  def active?
    cancelled_at.nil?
  end

  # 例外（個別変更）フラグを立てる
  def mark_as_exception!
    return if is_exception  # 既に例外フラグが立っている場合はスキップ
    update!(is_exception: true)
  end

  # 例外（個別変更）かどうか
  def exception?
    is_exception
  end

  def sync_to_apple_calendar
    # Apple Calendar APIとの同期処理
    # 後で実装
  end

  # === 繰り返しイベント機能 ===

  # 繰り返しスケジュールを生成（IceCubeを使用）
  def schedule
    return nil unless recurring? && recurrence_rule.present?

    @schedule ||= begin
      IceCube::Schedule.from_yaml(recurrence_rule)
    rescue => e
      Rails.logger.error "Failed to parse recurrence_rule in schedule method: #{e.message}"
      Rails.logger.error "recurrence_rule value: #{recurrence_rule.inspect}"
      nil
    end
  end

  # 指定期間内の繰り返しイベントの発生日時を取得
  def occurrences_between(start_date, end_date)
    return [] unless schedule

    # IceCubeのschedule.occurrences_betweenはTimeオブジェクトの配列を返すので、
    # それぞれをEventオブジェクトに変換する
    duration = end_time - start_time

    schedule.occurrences_between(start_date, end_date).map do |occurrence_time|
      # 元のイベントを複製して、個別の開始・終了時刻をセット
      cloned = self.dup
      cloned.id = self.id # 元のイベントIDを保持（親イベントとして識別）
      cloned.start_time = occurrence_time
      cloned.end_time = occurrence_time + duration
      cloned.is_virtual_occurrence = true # 仮想的な出現であることを示す
      cloned.occurrence_start_time = occurrence_time # 出現時刻を保存
      cloned.readonly! # 複製したオブジェクトは保存不可にする
      cloned
    end
  end

  # 繰り返しルールからIceCubeスケジュールを構築
  def self.build_schedule_from_params(start_time, recurrence_params)
    schedule = IceCube::Schedule.new(start_time)

    case recurrence_params[:frequency]
    when "daily"
      rule = IceCube::Rule.daily(recurrence_params[:interval].to_i)
    when "weekly"
      rule = IceCube::Rule.weekly(recurrence_params[:interval].to_i)
      if recurrence_params[:days_of_week].present?
        days = recurrence_params[:days_of_week].map(&:to_sym)
        rule = rule.day(*days)
      end
    when "monthly"
      rule = IceCube::Rule.monthly(recurrence_params[:interval].to_i)
    else
      return nil
    end

    # 終了条件の設定
    if recurrence_params[:end_type] == "date" && recurrence_params[:end_date].present?
      rule = rule.until(recurrence_params[:end_date].to_date)
    elsif recurrence_params[:end_type] == "count" && recurrence_params[:count].present?
      rule = rule.count(recurrence_params[:count].to_i)
    end

    schedule.add_recurrence_rule(rule)
    schedule
  end

  # 繰り返しイベントのインスタンスを生成
  def generate_recurring_instances!(up_to_date: 1.year.from_now)
    return unless recurring? && !recurring_event_id.present?

    # 既存のインスタンスを削除
    recurring_instances.destroy_all

    # 終了日の決定
    end_date = if recurrence_end_date.present?
      [ recurrence_end_date, up_to_date.to_date ].min
    else
      up_to_date.to_date
    end

    # IceCubeから直接Time配列を取得（occurrences_betweenメソッドはEventオブジェクト配列を返すため使用しない）
    occurrence_times = schedule.occurrences_between(start_time, end_date.end_of_day)

    # イベントの期間を計算
    duration = end_time - start_time

    # 最初の発生は親イベント自身なのでスキップ
    occurrence_times[1..-1]&.each do |occurrence_time|
      recurring_instances.create!(
        title: title,
        description: description,
        start_time: occurrence_time,
        end_time: occurrence_time + duration,
        original_start_time: occurrence_time,  # 元の発生時刻を保存
        location: location,
        all_day: all_day,
        status: status,
        event_type: event_type,
        color: color,
        character: character,
        user: user,
        reminder_minutes: reminder_minutes,
        recurring: false,  # インスタンスは繰り返しではない
        is_exception: false  # 初期状態では例外ではない
      )
    end
  end

  # 繰り返しイベントかどうか
  def recurring_parent?
    recurring? && recurring_event_id.nil?
  end

  # 繰り返しイベントのインスタンスかどうか
  def recurring_instance?
    recurring_event_id.present?
  end

  # 指定された開始時刻の子インスタンスを検索または作成
  # occurrence_timeは文字列またはTimeオブジェクト
  def find_or_initialize_occurrence(occurrence_time)
    return nil unless recurring_parent?

    # 文字列の場合はパース
    target_time = occurrence_time.is_a?(String) ? Time.zone.parse(occurrence_time) : occurrence_time

    # 時刻の前後1秒の範囲で検索（タイムゾーンのずれを吸収）
    time_range = (target_time - 1.second)..(target_time + 1.second)
    instance = recurring_instances.find_by(start_time: time_range)

    # 見つからない場合は新規インスタンスを作成（保存はしない）
    unless instance
      duration = end_time - start_time
      instance = recurring_instances.build(
        title: title,
        description: description,
        start_time: target_time,
        end_time: target_time + duration,
        original_start_time: target_time,  # 元の発生時刻を保存
        location: location,
        all_day: all_day,
        status: status,
        event_type: event_type,
        color: color,
        character: character,
        user: user,
        reminder_minutes: reminder_minutes,
        recurring: false,
        is_exception: false  # 初期状態では例外ではない
      )
    end

    instance
  end

  # 繰り返しルールの終了日を更新
  def update_recurrence_until!(end_date)
    return false unless recurring_parent? && recurrence_rule.present?

    begin
      schedule = IceCube::Schedule.from_yaml(recurrence_rule)
    rescue => e
      Rails.logger.error "Failed to parse recurrence_rule in update_recurrence_until!: #{e.message}"
      Rails.logger.error "recurrence_rule value: #{recurrence_rule.inspect}"
      return false
    end

    rules = schedule.rrules
    return false if rules.empty?

    rule = rules.first

    # 新しいスケジュールを作成（終了日をend_dateに設定）
    new_schedule = IceCube::Schedule.new(start_time)
    new_rule = rule.dup
    new_rule = new_rule.until(end_date.to_date)
    new_schedule.add_recurrence_rule(new_rule)

    update!(
      recurrence_rule: new_schedule.to_yaml,
      recurrence_end_date: end_date.to_date
    )
  end

  # 指定された開始時刻の子インスタンスを検索または作成（確実に保存）
  # occurrence_timeは文字列またはTimeオブジェクト
  # Googleカレンダーと同様に、親IDとoccurrence_timeから対象レコードを100%特定
  def find_or_create_occurrence!(occurrence_time)
    return nil unless recurring_parent?

    # 文字列の場合はパース
    target_time = occurrence_time.is_a?(String) ? Time.zone.parse(occurrence_time) : occurrence_time
    duration = end_time - start_time

    # 時刻の前後1秒の範囲で検索（タイムゾーンのずれを吸収）
    time_range = (target_time - 1.second)..(target_time + 1.second)

    # まず範囲検索で既存のインスタンスを探す
    instance = recurring_instances.find_by(start_time: time_range)

    # 見つからなければ新規作成
    unless instance
      instance = recurring_instances.create!(
        title: title,
        description: description,
        start_time: target_time,
        end_time: target_time + duration,
        original_start_time: target_time,  # 元の発生時刻を保存
        location: location,
        all_day: all_day,
        status: status,
        event_type: event_type,
        color: color,
        character: character,
        user: user,
        reminder_minutes: reminder_minutes,
        recurring: false,
        is_exception: false  # 初期状態では例外ではない
      )
      Rails.logger.info "📝 Created new occurrence: ID=#{instance.id}, start_time=#{instance.start_time.iso8601}"
    else
      Rails.logger.info "📝 Found existing occurrence: ID=#{instance.id}, start_time=#{instance.start_time.iso8601}"
    end

    instance
  end

  # 繰り返し設定を解析してハッシュで返す（フロントエンド用）
  def recurrence_settings
    return nil unless recurring? && recurrence_rule.present?

    begin
      schedule = IceCube::Schedule.from_yaml(recurrence_rule)
      rules = schedule.rrules
      return nil if rules.empty?

      rule = rules.first
      settings = {}

      # 頻度の判定
      if rule.is_a?(IceCube::DailyRule)
        settings[:frequency] = "daily"
      elsif rule.is_a?(IceCube::WeeklyRule)
        settings[:frequency] = "weekly"
      elsif rule.is_a?(IceCube::MonthlyRule)
        settings[:frequency] = "monthly"
      end

      # 間隔
      settings[:interval] = rule.interval || 1

      # 曜日（週次の場合）
      if rule.is_a?(IceCube::WeeklyRule) && rule.validations[:day]
        days_hash = rule.validations[:day].first
        settings[:days_of_week] = days_hash.keys.map(&:to_s) if days_hash
      end

      # 終了条件
      if recurrence_end_date.present?
        settings[:end_type] = "date"
        settings[:end_date] = recurrence_end_date.to_s
      elsif recurrence_count.present?
        settings[:end_type] = "count"
        settings[:count] = recurrence_count
      else
        settings[:end_type] = "never"
      end

      settings
    rescue => e
      Rails.logger.error "Failed to parse recurrence_rule in recurrence_settings: #{e.message}"
      Rails.logger.error "recurrence_rule value: #{recurrence_rule.inspect}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
      nil
    end
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

  def reset_reminder_sent_flag
    # line_reminded_at をリセット（reminder_minutes が変更されたとき）
    self.line_reminded_at = nil
  end
end
