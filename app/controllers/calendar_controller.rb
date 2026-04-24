class CalendarController < ApplicationController
  before_action :set_character
  before_action :set_date_params

  def index
    @view_type = params[:view] || "month"

    # すべてのビューで設定データを利用可能にする
    @calendar_settings = load_calendar_settings
    # イベントフォーム用のカテゴリをビューに渡す
    @custom_categories = @calendar_settings[:custom_categories] || default_categories

    case @view_type
    when "month"
      show_month
    when "week"
      show_week
    when "day"
      show_day
    else
      show_month
    end
  end

  def show
    @event = Event.find(params[:id])
    respond_to do |format|
      format.html { redirect_to calendar_index_path }
      format.json { render json: @event }
    end
  end

  def new
    @calendar_settings = load_calendar_settings
    @custom_categories = @calendar_settings[:custom_categories] || default_categories
    @event = Event.new

    # 開始時刻の設定（パラメータがあればそれを使用、なければ現在時刻の整時）
    @event.start_time = parse_datetime_param || Time.zone.now.beginning_of_hour

    # 終了時刻はデフォルトで開始時刻から1時間後に設定
    @event.end_time = @event.start_time + 1.hour
  end

  def create
    Rails.logger.info "📝 Event creation started"
    Rails.logger.info "📝 Params: #{params.inspect}"
    Rails.logger.info "📝 Event params: #{event_params.inspect}"

    @event = Event.new(event_params)
    @event.character = @character

    Rails.logger.info "📝 Event object: #{@event.inspect}"
    Rails.logger.info "📝 Event valid?: #{@event.valid?}"
    Rails.logger.info "📝 Event errors: #{@event.errors.full_messages}" unless @event.valid?

    if @event.save
      Rails.logger.info "📝 Event saved successfully: #{@event.id}"
      # タスクの期限などもカレンダーに同期
      sync_tasks_to_calendar if @event.task_deadline?

      respond_to do |format|
        format.html { redirect_to calendar_index_path(date: @event.start_time.to_date), notice: "イベントが作成されました。" }
        format.json { render json: { success: true, event: @event }, status: :created }
      end
    else
      Rails.logger.error "📝 Event save failed: #{@event.errors.full_messages}"
      respond_to do |format|
        format.html { redirect_to calendar_index_path, alert: "イベントの作成に失敗しました: #{@event.errors.full_messages.join(', ')}" }
        format.json { render json: { success: false, errors: @event.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  rescue => e
    Rails.logger.error "📝 Exception in create: #{e.message}"
    Rails.logger.error "📝 Backtrace: #{e.backtrace.first(5)}"
    respond_to do |format|
      format.html { redirect_to calendar_index_path, alert: "エラーが発生しました: #{e.message}" }
      format.json { render json: { success: false, error: e.message }, status: :internal_server_error }
    end
  end

  def edit
    @calendar_settings = load_calendar_settings
    @custom_categories = @calendar_settings[:custom_categories] || default_categories
    @event = Event.find(params[:id])
  end

  def update
    @event = Event.find(params[:id])

    Rails.logger.info "📝 Event update started for ID: #{@event.id}"
    Rails.logger.info "📝 Update params: #{event_params.inspect}"

    if @event.update(event_params)
      Rails.logger.info "📝 Event updated successfully: #{@event.id}"
      respond_to do |format|
        format.html { redirect_to calendar_index_path(date: @event.start_time.to_date), notice: "イベントが更新されました。" }
        format.json { render json: { success: true, event: @event }, status: :ok }
      end
    else
      Rails.logger.error "📝 Event update failed: #{@event.errors.full_messages}"
      respond_to do |format|
        format.html { redirect_to calendar_index_path, alert: "イベントの更新に失敗しました: #{@event.errors.full_messages.join(', ')}" }
        format.json { render json: { success: false, errors: @event.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  rescue => e
    Rails.logger.error "📝 Exception in update: #{e.message}"
    Rails.logger.error "📝 Backtrace: #{e.backtrace.first(5)}"
    respond_to do |format|
      format.html { redirect_to calendar_index_path, alert: "エラーが発生しました: #{e.message}" }
      format.json { render json: { success: false, error: e.message }, status: :internal_server_error }
    end
  end

  def destroy
    @event = Event.find(params[:id])

    Rails.logger.info "📝 Event deletion started for ID: #{@event.id}"

    if @event.destroy
      Rails.logger.info "📝 Event deleted successfully: #{@event.id}"
      respond_to do |format|
        format.html { redirect_to calendar_index_path, notice: "イベントが削除されました。" }
        format.json { render json: { success: true, message: "イベントが削除されました。" }, status: :ok }
      end
    else
      Rails.logger.error "📝 Event deletion failed: #{@event.errors.full_messages}"
      respond_to do |format|
        format.html { redirect_to calendar_index_path, alert: "イベントの削除に失敗しました: #{@event.errors.full_messages.join(', ')}" }
        format.json { render json: { success: false, errors: @event.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  rescue => e
    Rails.logger.error "📝 Exception in destroy: #{e.message}"
    Rails.logger.error "📝 Backtrace: #{e.backtrace.first(5)}"
    respond_to do |format|
      format.html { redirect_to calendar_index_path, alert: "エラーが発生しました: #{e.message}" }
      format.json { render json: { success: false, error: e.message }, status: :internal_server_error }
    end
  end

  # 設定画面
  def settings
    @calendar_settings = load_calendar_settings
    @color_options = color_options
  end

  # 設定更新
  def update_settings
    update_calendar_settings(settings_params)
    redirect_to settings_calendar_index_path, notice: "設定が更新されました。"
  end

  # APIエンドポイント（JSON形式でイベント取得）
  def events
    start_date = Date.parse(params[:start]) rescue @date.beginning_of_month
    end_date = Date.parse(params[:end]) rescue @date.end_of_month

    events = Event.for_date_range(start_date, end_date)
                  .includes(:character)

    # カスタムカテゴリの設定を取得
    settings = load_calendar_settings
    custom_categories = settings[:custom_categories] || default_categories

    calendar_events = events.map do |event|
      # イベントタイプに対応するカテゴリの色を取得
      category = custom_categories.find { |cat| (cat[:id] || cat["id"]) == event.event_type }
      event_color = category ? (category[:color] || category["color"]) : event.display_color

      {
        id: event.id,
        title: event.title,
        start: event.start_time.iso8601,
        end: event.end_time.iso8601,
        allDay: event.all_day?,
        backgroundColor: event_color,
        borderColor: event_color,
        description: event.description,
        location: event.location,
        eventType: event.event_type,
        status: event.status
      }
    end

    render json: calendar_events
  end

  # 外部カレンダー連携
  def sync_external
    sync_type = params[:sync_type] # 'google' or 'apple'

    case sync_type
    when "google"
      sync_with_google_calendar
    when "apple"
      sync_with_apple_calendar
    end

    redirect_to calendar_index_path, notice: "#{sync_type.capitalize}カレンダーとの同期を開始しました。"
  end

  private

  def set_character
    @character = Character.find_by(id: 1) || Character.first
  end

  def create_sample_events
    # 開発環境でのみサンプルイベントを作成（本番環境では実行しない）
    return unless Rails.env.development? && @character.present?

    # 手動で有効化する場合にのみ実行（デフォルトでは無効）
    return unless Rails.application.config.enable_sample_events

    sample_events = [
      {
        title: "🎯 チーム定期ミーティング",
        description: "週次チームミーティング",
        start_time: Time.zone.today.beginning_of_month + 10.days + 10.hours,
        end_time: Time.zone.today.beginning_of_month + 10.days + 11.hours,
        event_type: "meeting"
      },
      {
        title: "🎂 誕生日パーティー",
        description: "友人の誕生日お祝い",
        start_time: Time.zone.today + 3.days + 18.hours,
        end_time: Time.zone.today + 3.days + 21.hours,
        event_type: "personal"
      },
      {
        title: "💻 コードレビュー",
        description: "新機能のコードレビュー",
        start_time: Time.zone.today + 5.days + 14.hours,
        end_time: Time.zone.today + 5.days + 16.hours,
        event_type: "work"
      }
    ]

    sample_events.each do |event_data|
      Event.create!(event_data.merge(character: @character))
    end
  end

  def set_date_params
    @date = params[:date] ? Date.parse(params[:date]) : Time.zone.today
    @year = @date.year
    @month = @date.month
  rescue Date::Error
    @date = Time.zone.today
    @year = @date.year
    @month = @date.month
  end

  def parse_datetime_param
    return nil unless params[:datetime]
    DateTime.parse(params[:datetime])
  rescue ArgumentError
    nil
  end

  def show_month
    Rails.logger.info "📅 CalendarController#show_month called"
    @start_date = @date.beginning_of_month.beginning_of_week(:sunday)
    @end_date = @date.end_of_month.end_of_week(:sunday)

    Rails.logger.info "📅 Date range: #{@start_date} - #{@end_date}"

    @events = Event.for_date_range(@start_date, @end_date).includes(:character)
    Rails.logger.info "📅 Found #{@events.count} events"

    # 祝日データを取得（設定により表示/非表示切り替え）
    @holidays = @calendar_settings[:show_holidays] ?
                Holiday.where(date: @start_date..@end_date, country: "JP") :
                Holiday.none

    @calendar_weeks = build_calendar_weeks(@start_date, @end_date)
    Rails.logger.info "📅 Built #{@calendar_weeks.length} calendar weeks"

    # サンプルイベント作成機能は無効化（本番環境では不要）
    # if @events.empty? && @character.present?
    #   Rails.logger.info "📅 Creating sample events"
    #   create_sample_events
    #   @events = Event.for_date_range(@start_date, @end_date).includes(:character)
    #   @calendar_weeks = build_calendar_weeks(@start_date, @end_date)
    #   Rails.logger.info "📅 After creating samples: #{@events.count} events, #{@calendar_weeks.length} weeks"
    # end
  end

  def show_week
    @start_date = @date.beginning_of_week(:sunday)
    @end_date = @date.end_of_week(:sunday)
    @events = Event.for_date_range(@start_date, @end_date).includes(:character)

    # 週表示用の祝日データ取得
    @holidays = @calendar_settings[:show_holidays] ?
                Holiday.where(date: @start_date..@end_date, country: "JP") :
                Holiday.none

    @week_days = (@start_date..@end_date).map { |date| date }
  end

  def show_day
    @start_date = @date.beginning_of_day
    @end_date = @date.end_of_day
    @events = Event.for_date_range(@start_date, @end_date)
                   .order(:start_time)
                   .includes(:character)

    # 日表示用の祝日データ取得
    @holidays = @calendar_settings[:show_holidays] ?
                Holiday.where(date: @date, country: "JP") :
                Holiday.none

    @hourly_events = build_hourly_events(@events)
  end

  def build_calendar_weeks(start_date, end_date)
    Rails.logger.info "📅 Building calendar weeks from #{start_date} to #{end_date}"
    weeks = []
    current_date = start_date

    while current_date <= end_date
      week_days = []
      7.times do
        day_events = @events.select { |event|
          event_date_range = (event.start_time.to_date..event.end_time.to_date)
          event_date_range.include?(current_date)
        }

        # 祝日情報を取得
        day_holiday = @holidays&.find { |holiday| holiday.date == current_date }

        day_data = {
          date: current_date,
          events: day_events,
          current_month: current_date.month == @month,
          today: current_date == Time.zone.today,
          holiday: day_holiday,
          is_weekend: current_date.saturday? || current_date.sunday?
        }

        week_days << day_data
        Rails.logger.debug "📅 Day #{current_date}: #{day_events.count} events, current_month: #{day_data[:current_month]}, holiday: #{day_holiday&.name}"
        current_date += 1.day
      end
      weeks << week_days
    end

    Rails.logger.info "📅 Built #{weeks.length} weeks with #{weeks.flatten.count} total days"
    weeks
  end

  def build_hourly_events(events)
    hourly = {}

    (0..23).each do |hour|
      hour_start = @date.beginning_of_day + hour.hours
      hour_end = hour_start + 1.hour

      hourly[hour] = events.select do |event|
        (event.start_time < hour_end) && (event.end_time > hour_start)
      end
    end

    hourly
  end

  def sync_tasks_to_calendar
    # アクティビティ（タスク）の期限をカレンダーイベントとして同期
    activities_with_deadlines = Activity.where.not(deadline: nil)

    activities_with_deadlines.each do |activity|
      existing_event = Event.find_by(external_id: "activity_#{activity.id}")

      if existing_event
        # 既存イベントを更新
        existing_event.update!(
          title: "📋 #{activity.title} (期限)",
          start_time: activity.deadline.beginning_of_day,
          end_time: activity.deadline.end_of_day,
          description: activity.description&.truncate(100)
        )
      else
        # 新規イベントを作成
        Event.create_from_task(activity)
      end
    end
  end

  def sync_with_google_calendar
    # Google Calendar APIとの同期
    # 実装は後で行う（Google Calendar Gem使用）
    Rails.logger.info "🔄 Google Calendar sync requested"
  end

  def sync_with_apple_calendar
    # Apple Calendar APIとの同期
    # 実装は後で行う
    Rails.logger.info "🔄 Apple Calendar sync requested"
  end

  def event_params
    params.require(:event).permit(:title, :description, :start_time, :end_time, :location,
                                  :all_day, :event_type, :status, :color, :attendees)
  end
  # カレンダー設定関連
  def load_calendar_settings
    settings = {
      show_holidays: true,
      show_weekends: true,
      show_task_deadlines: true,
      default_view: "month",
      start_week_on: "sunday",
      timezone: "Asia/Tokyo",
      custom_categories: [
        { id: "personal", name: "個人", color: "#3B82F6" },
        { id: "work", name: "仕事", color: "#10B981" },
        { id: "meeting", name: "ミーティング", color: "#F59E0B" },
        { id: "task_deadline", name: "タスク期限", color: "#EF4444" }
      ]
    }

    # ユーザーの設定があれば読み込み
    if @character&.calendar_settings.present?
      user_settings = JSON.parse(@character.calendar_settings)
      # 文字列キーのハッシュをシンボルキーに変換（ただしcustom_categoriesは文字列キーのまま保持）
      user_settings.each do |key, value|
        unless key == "custom_categories"
          settings[key.to_sym] = value
        else
          # custom_categoriesがハッシュ（インデックス付き）の場合は配列に変換
          if value.is_a?(Hash) && value.keys.all? { |k| k =~ /^\d+$/ }
            # インデックス付きハッシュを配列に変換
            settings[:custom_categories] = value.values
          else
            settings[:custom_categories] = value
          end
        end
      end
    end

    settings
  rescue JSON::ParserError
    # JSON解析エラーの場合はデフォルト設定を返す
    {
      show_holidays: true,
      show_weekends: true,
      show_task_deadlines: true,
      default_view: "month",
      start_week_on: "sunday",
      timezone: "Asia/Tokyo",
      custom_categories: [
        { id: "personal", name: "個人", color: "#3B82F6" },
        { id: "work", name: "仕事", color: "#10B981" },
        { id: "meeting", name: "ミーティング", color: "#F59E0B" },
        { id: "task_deadline", name: "タスク期限", color: "#EF4444" }
      ]
    }
  end

  def update_calendar_settings(new_settings)
    if @character
      # ActionController::Parametersを安全にハッシュに変換
      settings_hash = new_settings.to_unsafe_h

      # カスタムカテゴリの処理
      if settings_hash["custom_categories"].present?
        processed_categories = []

        settings_hash["custom_categories"].each do |index, category_data|
          if category_data.is_a?(Hash) && category_data["name"].present?
            processed_categories << {
              "id" => category_data["id"] || "custom_#{index}",
              "name" => category_data["name"],
              "color" => category_data["color"] || "#3B82F6"
            }
          end
        end

        settings_hash["custom_categories"] = processed_categories
      else
        # カスタムカテゴリがない場合はデフォルトを設定
        settings_hash["custom_categories"] = default_categories.map(&:stringify_keys)
      end

      @character.update!(calendar_settings: settings_hash.to_json)
    end
  end

  def settings_params
    params.require(:settings).permit(
      :show_holidays, :show_weekends, :show_task_deadlines,
      :default_view, :start_week_on, :timezone,
      custom_categories: {}
    )
  end

  def default_categories
    [
      { id: "personal", name: "個人", color: "#3B82F6" },
      { id: "work", name: "仕事", color: "#10B981" },
      { id: "meeting", name: "ミーティング", color: "#F59E0B" },
      { id: "task_deadline", name: "タスク期限", color: "#EF4444" }
    ]
  end

  def color_options
    [
      { name: "ブルー", value: "#3B82F6" },
      { name: "グリーン", value: "#10B981" },
      { name: "イエロー", value: "#F59E0B" },
      { name: "レッド", value: "#EF4444" },
      { name: "パープル", value: "#8B5CF6" },
      { name: "ピンク", value: "#EC4899" },
      { name: "オレンジ", value: "#F97316" },
      { name: "シアン", value: "#06B6D4" },
      { name: "グレー", value: "#6B7280" },
      { name: "インディゴ", value: "#6366F1" }
    ]
  end
end
