class CalendarController < ApplicationController
  # 祝日イベントを表すクラス（Eventモデルと同じインターフェースを提供）
  class HolidayEvent
    attr_accessor :id, :title, :start_time, :end_time, :all_day, :description,
                  :location, :event_type, :status, :color, :character, :is_holiday,
                  :category, :reminder_minutes

    def initialize(attributes = {})
      attributes.each do |key, value|
        send("#{key}=", value) if respond_to?("#{key}=")
      end
    end

    def all_day?
      @all_day
    end

    def recurring?
      false
    end

    def recurring_parent?
      false
    end

    def recurring_instance?
      false
    end

    def recurring_event_id
      nil
    end

    def character_id
      @character&.id
    end

    def display_category_name
      @title
    end

    def display_color
      @color || "#DC2626"
    end

    def as_json(options = {})
      {
        id: @id,
        title: @title,
        start_time: @start_time,
        end_time: @end_time,
        all_day: @all_day,
        is_holiday: @is_holiday,
        event_type: @event_type,
        category: @category,
        color: @color
      }
    end
  end

  before_action :set_character
  before_action :set_date_params, except: [ :settings, :update_settings ]

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
    # セキュリティ: 現在のユーザーのイベントのみアクセス可能
    @event = @character.events.find(params[:id])

    # JSONレスポンス用のハッシュを準備
    response_data = @event.as_json.merge(
      recurring: @event.recurring?,
      recurring_event_id: @event.recurring_event_id,
      recurrence_settings: @event.recurrence_settings
    )

    # 繰り返しインスタンスの場合、occurrence_timeの情報を追加
    if params[:occurrence_time].present? && @event.recurring_parent?
      occurrence_time = Time.zone.parse(params[:occurrence_time])
      duration = @event.end_time - @event.start_time

      Rails.logger.info "📝 Show event - parent_id: #{@event.id}, occurrence_time: #{occurrence_time.iso8601}"

      # 親イベントのIDはそのままで、start_timeとend_timeをオカレンスの時刻に変更
      response_data["start_time"] = occurrence_time.iso8601
      response_data["end_time"] = (occurrence_time + duration).iso8601
      response_data["occurrence_time"] = occurrence_time.iso8601  # 明示的に追加
      response_data["is_occurrence"] = true
    elsif @event.recurring_event_id.present?
      # 既に作成された子インスタンスの場合
      Rails.logger.info "📝 Show event - child instance, id: #{@event.id}, parent_id: #{@event.recurring_event_id}"
      # original_start_time があればそれを、なければ start_time を occurrence_time として使用
      occurrence_time = @event.original_start_time || @event.start_time
      response_data["occurrence_time"] = occurrence_time.iso8601
      response_data["is_occurrence"] = true
    end

    respond_to do |format|
      format.html { redirect_to calendar_index_path }
      format.json { render json: response_data }
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
    Rails.logger.info "📝 Recurring checkbox value: #{params[:event][:recurring].inspect}"
    Rails.logger.info "📝 Recurrence params present?: #{params[:event][:recurrence].present?}"
    Rails.logger.info "📝 Recurrence params: #{params[:event][:recurrence].inspect}" if params[:event][:recurrence].present?

    @event = Event.new(normalized_event_attributes)
    @event.character = @character

    # 繰り返しイベントの処理
    if params[:event][:recurring] == "1" && params[:event][:recurrence].present?
      Rails.logger.info "📝 ✅ Recurring event detected - building schedule"
      recurrence_params = params[:event][:recurrence]
      schedule = Event.build_schedule_from_params(@event.start_time, recurrence_params)

      if schedule
        Rails.logger.info "📝 ✅ Schedule built successfully"
        @event.recurrence_rule = schedule.to_yaml
        @event.recurring = true

        # 終了日の設定
        if recurrence_params[:end_type] == "date" && recurrence_params[:end_date].present?
          @event.recurrence_end_date = recurrence_params[:end_date].to_date
        elsif recurrence_params[:end_type] == "count" && recurrence_params[:count].present?
          @event.recurrence_count = recurrence_params[:count].to_i
        end
      else
        Rails.logger.error "📝 ❌ Failed to build schedule from recurrence params"
      end
    else
      Rails.logger.info "📝 ⚠️ Not a recurring event (recurring: #{params[:event][:recurring].inspect}, recurrence present: #{params[:event][:recurrence].present?})"
    end

    Rails.logger.info "📝 Event object: #{@event.inspect}"
    Rails.logger.info "📝 Event valid?: #{@event.valid?}"
    Rails.logger.info "📝 Event errors: #{@event.errors.full_messages}" unless @event.valid?

    if @event.save
      Rails.logger.info "📝 Event saved successfully: #{@event.id}"

      # 繰り返しイベントのインスタンスを生成
      if @event.recurring?
        @event.generate_recurring_instances!(up_to_date: 1.year.from_now)
      end

      # タスクの期限などもカレンダーに同期
      # sync_tasks_to_calendar if @event.task_deadline?  # DISABLED: Activity.deadline does not exist

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
    # セキュリティ: 現在のユーザーのイベントのみアクセス可能
    @event = @character.events.find(params[:id])
  end

  def update
    # 1. まず送られてきたIDでイベントを取得
    base_event = @character.events.find(params[:id])
    scope = params[:edit_scope] || "one"

    Rails.logger.info "📝 Event update - ID: #{base_event.id}, recurring: #{base_event.recurring?}, occurrence_time: #{params[:occurrence_time]}, scope: #{scope}"

    # 2. 親イベント + occurrence_time の場合、該当する子レコードを特定・作成
    @event = base_event

    # 繰り返しイベントの親で、occurrence_timeが指定されていない、かつscope="one"の場合はエラー
    if base_event.recurring_parent? && params[:occurrence_time].blank? && scope == "one"
      Rails.logger.error "📝 ERROR: Attempting to edit recurring parent without occurrence_time"
      respond_to do |format|
        format.html { redirect_to calendar_index_path, alert: "エラー: 繰り返しイベントの特定の日を編集する場合は、カレンダーからその日をクリックして編集してください。" }
        format.json { render json: { success: false, error: "occurrence_timeが必要です" }, status: :unprocessable_entity }
      end
      return
    end

    if params[:occurrence_time].present?
      occurrence_time = Time.zone.parse(params[:occurrence_time])
      Rails.logger.info "📝 Parsed occurrence_time: #{occurrence_time.iso8601}"

      # 親イベントの場合、該当する子インスタンスを取得または作成（確実に保存）
      if base_event.recurring_parent?
        @event = base_event.find_or_create_occurrence!(occurrence_time)
        Rails.logger.info "📝 Target event created/found: ID=#{@event.id}, start_time=#{@event.start_time.iso8601}"
      elsif base_event.recurring_instance?
        # 既に子インスタンスの場合はそのまま使用
        @event = base_event
        Rails.logger.info "📝 Using existing child instance: ID=#{@event.id}"
      end
    end

    Rails.logger.info "📝 Update params: #{event_params.inspect}"

    # 3. 特定した @event を基準に、スコープ別の更新を実行

    begin
      case scope
      when "one"
        # この予定のみを更新
        handle_single_event_update

      when "future"
        # これ以降のすべての予定を更新
        handle_future_events_update

      when "all"
        # すべての予定（シリーズ全体）を更新
        handle_all_events_update

      else
        # デフォルトは「この予定のみ」
        handle_single_event_update
      end

      Rails.logger.info "📝 Event updated successfully with scope: #{scope}"
      respond_to do |format|
        format.html { redirect_to calendar_index_path(date: @event.start_time.to_date), notice: "イベントが更新されました。" }
        format.json { render json: { success: true, event: @event }, status: :ok }
      end
    rescue => e
      Rails.logger.error "📝 Exception in update: #{e.message}"
      Rails.logger.error "📝 Backtrace: #{e.backtrace.first(5)}"
      respond_to do |format|
        format.html { redirect_to calendar_index_path, alert: "エラーが発生しました: #{e.message}" }
        format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    # 1. まず送られてきたIDでイベントを取得
    base_event = @character.events.find(params[:id])
    scope = params[:delete_scope] || "one"

    Rails.logger.info "📝 Event deletion - ID: #{base_event.id}, recurring: #{base_event.recurring?}, recurring_parent: #{base_event.recurring_parent?}, occurrence_time: #{params[:occurrence_time]}, scope: #{scope}"
    Rails.logger.info "📝 Base event details - start_time: #{base_event.start_time}, recurring_event_id: #{base_event.recurring_event_id}"

    # 2. 親イベント + occurrence_time の場合、該当する子レコードを特定・作成
    target_event = base_event
    occurrence_time = nil

    if params[:occurrence_time].present?
      occurrence_time = Time.zone.parse(params[:occurrence_time])
      Rails.logger.info "📝 Parsed occurrence_time: #{occurrence_time.iso8601}"

      # 親イベントの場合、該当する子インスタンスを取得または作成（確実に保存）
      if base_event.recurring_parent?
        Rails.logger.info "📝 Base event is recurring parent, creating/finding occurrence"
        target_event = base_event.find_or_create_occurrence!(occurrence_time)
        Rails.logger.info "📝 Target event created/found: ID=#{target_event.id}, start_time=#{target_event.start_time.iso8601}"
      elsif base_event.recurring_instance?
        # 既に子インスタンスの場合はそのまま使用
        target_event = base_event
        Rails.logger.info "📝 Using existing child instance: ID=#{target_event.id}"
      else
        Rails.logger.info "📝 Base event is neither parent nor child, using as-is"
      end
    else
      Rails.logger.info "📝 No occurrence_time provided"
    end

    # 3. 特定した target_event を基準に、スコープ別の削除を実行
    Rails.logger.info "📝 Proceeding with deletion - target_event ID: #{target_event.id}, scope: #{scope}"
    Rails.logger.info "📝 Target event is recurring_parent?: #{target_event.recurring_parent?}, recurring_instance?: #{target_event.recurring_instance?}"
    Rails.logger.info "📝 Target event recurring_event_id: #{target_event.recurring_event_id}"

    begin
      case scope
      when "one"
        # この予定のみを論理削除（カレンダーから非表示にするが、データは残す）
        Rails.logger.info "📝 About to soft delete event ID: #{target_event.id}"
        target_event.soft_delete!
        Rails.logger.info "📝 Soft deleted event: ID=#{target_event.id}, cancelled_at: #{target_event.cancelled_at}"
        message = "イベントが削除されました。"

      when "future"
        # これ以降のすべての予定を削除
        parent_event = target_event.recurring_event || (target_event.recurring_parent? ? target_event : nil)

        if parent_event
          # この日以降の子インスタンスを削除
          deleted_count = parent_event.recurring_instances.where("start_time >= ?", target_event.start_time).destroy_all.count
          Rails.logger.info "📝 Deleted #{deleted_count} future instances"

          # 親イベントの繰り返し終了日を更新（この日の前日に設定）
          new_end_date = target_event.start_time.to_date - 1.day
          parent_event.update_recurrence_until!(new_end_date)

          message = "選択した日以降の予定が削除されました。"
        else
          # 通常のイベントの場合
          target_event.destroy!
          message = "イベントが削除されました。"
        end

      when "all"
        # すべての予定（シリーズ全体）を削除
        parent_event = target_event.recurring_event || (target_event.recurring_parent? ? target_event : nil)

        if parent_event
          # 親を削除（dependent: :destroyで子も削除される）
          parent_event.destroy!
          message = "繰り返し予定のシリーズ全体が削除されました。"
        else
          # 通常のイベントの場合
          target_event.destroy!
          message = "イベントが削除されました。"
        end

      else
        # デフォルトは「この予定のみ」
        target_event.destroy!
        message = "イベントが削除されました。"
      end

      Rails.logger.info "📝 Event deleted successfully with scope: #{scope}"
      respond_to do |format|
        format.html { redirect_to calendar_index_path, notice: message }
        format.json { render json: { success: true, message: message }, status: :ok }
      end
    rescue => e
      Rails.logger.error "📝 Exception in destroy: #{e.message}"
      Rails.logger.error "📝 Backtrace: #{e.backtrace.first(5)}"
      respond_to do |format|
        format.html { redirect_to calendar_index_path, alert: "エラーが発生しました: #{e.message}" }
        format.json { render json: { success: false, error: e.message }, status: :internal_server_error }
      end
    end
  end

  private

  def handle_single_event_update
    # 日付変更の検証用に属性を取得
    new_attributes = normalized_event_attributes

    # 繰り返しイベントの子の場合、例外フラグを立てる
    if @event.recurring_event_id.present?
      # 日付が変更される場合、元の日付に論理削除されたレコードを作成
      original_date = @event.original_start_time || @event.start_time

      # 一時的に属性を適用して新しい日時を取得（まだ保存しない）
      temp_event = @event.dup
      temp_event.assign_attributes(new_attributes)
      new_date = temp_event.start_time

      # 日付が変更された場合のみ処理
      if original_date.to_date != new_date.to_date
        # 元の日付に論理削除されたダミーレコードを作成
        parent = @event.recurring_event
        duration = @event.end_time - @event.start_time

        parent.recurring_instances.create!(
          title: @event.title,
          description: @event.description,
          start_time: original_date,
          end_time: original_date + duration,
          original_start_time: original_date,
          location: @event.location,
          all_day: @event.all_day,
          status: @event.status,
          event_type: @event.event_type,
          color: @event.color,
          character: @event.character,
          user: @event.user,
          reminder_minutes: @event.reminder_minutes,
          recurring: false,
          is_exception: true,
          cancelled_at: Time.current  # 論理削除済みとしてマーク
        )

        Rails.logger.info "📝 Created cancelled dummy record for original date: #{original_date.to_date}"
      end

      # original_start_time が未設定の場合のみ設定（一度設定したら変更しない）
      if @event.original_start_time.blank?
        new_attributes[:original_start_time] = original_date
      end

      # 例外フラグを立てる（new_attributes に含める）
      new_attributes[:is_exception] = true

      # 親から独立させて単発イベントとして更新する場合はコメントを外す
      # @event.recurring_event_id = nil
      # @event.recurring = false
      # @event.recurrence_rule = nil
      # @event.recurrence_end_date = nil
      # @event.recurrence_count = nil
    end

    # 通常の更新処理
    if @event.update(new_attributes)
      # タスク期限イベントの場合、対応するタスクのdescriptionも更新
      if @event.task_deadline? && @event.external_id&.start_with?("task_")
        task_id = @event.external_id.sub("task_", "").to_i
        task = @character&.tasks&.find_by(id: task_id)
        if task
          event_desc = @event.description.to_s
          custom_desc = event_desc.include?("\n\n") ? event_desc.split("\n\n", 2).last.presence : nil
          task.update_columns(description: custom_desc)
        end
      end
    else
      raise "更新に失敗しました: #{@event.errors.full_messages.join(', ')}"
    end
  end

  def handle_future_events_update
    parent_event = @event.recurring_event_id.present? ? @event.recurring_event : @event

    return handle_single_event_update unless parent_event

    # この日以降の兄弟イベントを削除
    if @event.recurring_event_id.present?
      parent_event.recurring_instances.where("start_time >= ?", @event.start_time).destroy_all
    else
      # 親イベント自身の場合も、今日以降の子を削除
      parent_event.recurring_instances.destroy_all
    end

    # 新しい繰り返し設定の処理
    if params[:event][:recurring] == "1" && params[:event][:recurrence].present?
      recurrence_params = params[:event][:recurrence]

      # 更新後の開始時刻を取得
      updated_attrs = normalized_event_attributes
      start_time = updated_attrs["start_time"] || @event.start_time

      schedule = Event.build_schedule_from_params(start_time, recurrence_params)

      if schedule
        # 新しい親イベントを作成または既存の親を更新
        if @event.recurring_event_id.present?
          # 子イベントの場合、新しい親イベントを作成
          new_parent = @character.events.create!(
            title: updated_attrs["title"] || @event.title,
            description: updated_attrs["description"] || @event.description,
            start_time: start_time,
            end_time: updated_attrs["end_time"] || @event.end_time,
            location: updated_attrs["location"] || @event.location,
            all_day: updated_attrs["all_day"] || @event.all_day,
            status: updated_attrs["status"] || @event.status,
            event_type: updated_attrs["event_type"] || @event.event_type,
            color: updated_attrs["color"] || @event.color,
            user: @event.user,
            reminder_minutes: updated_attrs["reminder_minutes"] || @event.reminder_minutes,
            recurring: true,
            recurrence_rule: schedule.to_yaml
          )

          # 終了日の設定
          if recurrence_params[:end_type] == "date" && recurrence_params[:end_date].present?
            new_parent.recurrence_end_date = recurrence_params[:end_date].to_date
          elsif recurrence_params[:end_type] == "count" && recurrence_params[:count].present?
            new_parent.recurrence_count = recurrence_params[:count].to_i
          end
          new_parent.save!

          # 新しいインスタンスを生成
          new_parent.generate_recurring_instances!(up_to_date: 1.year.from_now)

          # 元のイベントは削除
          @event.destroy
          @event = new_parent
        else
          # 親イベント自身の場合、親を更新
          @event.recurrence_rule = schedule.to_yaml
          @event.recurring = true

          if recurrence_params[:end_type] == "date" && recurrence_params[:end_date].present?
            @event.recurrence_end_date = recurrence_params[:end_date].to_date
          elsif recurrence_params[:end_type] == "count" && recurrence_params[:count].present?
            @event.recurrence_count = recurrence_params[:count].to_i
          else
            @event.recurrence_end_date = nil
            @event.recurrence_count = nil
          end

          if @event.update(normalized_event_attributes)
            @event.generate_recurring_instances!(up_to_date: 1.year.from_now)
          else
            raise "更新に失敗しました: #{@event.errors.full_messages.join(', ')}"
          end
        end
      end
    else
      # 繰り返し設定がない場合、単発イベントとして更新
      handle_single_event_update
    end
  end

  def handle_all_events_update
    parent_event = @event.recurring_event_id.present? ? @event.recurring_event : @event

    return handle_single_event_update unless parent_event

    # 親イベントを更新
    target_event = parent_event

    # 繰り返しイベントの処理
    if params[:event][:recurring] == "1" && params[:event][:recurrence].present?
      recurrence_params = params[:event][:recurrence]

      # 開始時刻を取得（更新後の値を使用）
      updated_attrs = normalized_event_attributes
      start_time = updated_attrs["start_time"] || target_event.start_time

      schedule = Event.build_schedule_from_params(start_time, recurrence_params)

      if schedule
        target_event.recurrence_rule = schedule.to_yaml
        target_event.recurring = true

        # 終了日の設定
        if recurrence_params[:end_type] == "date" && recurrence_params[:end_date].present?
          target_event.recurrence_end_date = recurrence_params[:end_date].to_date
        elsif recurrence_params[:end_type] == "count" && recurrence_params[:count].present?
          target_event.recurrence_count = recurrence_params[:count].to_i
        else
          target_event.recurrence_end_date = nil
          target_event.recurrence_count = nil
        end
      end
    else
      # 繰り返し設定が無効化された場合
      target_event.recurring = false
      target_event.recurrence_rule = nil
      target_event.recurrence_end_date = nil
      target_event.recurrence_count = nil
    end

    if target_event.update(normalized_event_attributes)
      # 繰り返しイベントのインスタンスを再生成
      if target_event.recurring?
        # 既存のインスタンスを削除して再生成
        target_event.recurring_instances.destroy_all
        target_event.generate_recurring_instances!(up_to_date: 1.year.from_now)
      else
        # 繰り返しが無効化された場合は、子インスタンスを削除
        target_event.recurring_instances.destroy_all
      end

      # タスク期限イベントの場合、対応するタスクのdescriptionも更新
      if target_event.task_deadline? && target_event.external_id&.start_with?("task_")
        task_id = target_event.external_id.sub("task_", "").to_i
        task = @character&.tasks&.find_by(id: task_id)
        if task
          event_desc = target_event.description.to_s
          custom_desc = event_desc.include?("\n\n") ? event_desc.split("\n\n", 2).last.presence : nil
          task.update_columns(description: custom_desc)
        end
      end

      @event = target_event
    else
      raise "更新に失敗しました: #{target_event.errors.full_messages.join(', ')}"
    end
  end

  # 以下のアクションはpublicとして定義
  public

  # 設定画面
  def settings
    @calendar_settings = load_calendar_settings || {
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

    # セキュリティ: 現在のユーザーのキャラクターに紐づくイベントのみ取得
    # 論理削除されたイベントは除外
    @events = @character.events.active.for_date_range(start_date, end_date).to_a

    # 祝日を追加（設定により表示/非表示切り替え）
    settings = load_calendar_settings
    if settings[:show_holidays]
      add_holiday_events(start_date, end_date)
    end

    # カスタムカテゴリの設定を取得
    custom_categories = settings[:custom_categories] || default_categories

    calendar_events = @events.map do |event|
      # 祝日イベントの場合
      if event.is_a?(HolidayEvent)
        {
          id: event.id,
          title: event.title,
          start: event.start_time.iso8601,
          end: event.end_time.iso8601,
          allDay: event.all_day?,
          backgroundColor: event.color,
          borderColor: event.color,
          description: event.description,
          location: event.location,
          eventType: event.event_type,
          event_type: event.event_type,
          start_time: event.start_time.iso8601,
          end_time: event.end_time.iso8601,
          reminder_minutes: event.reminder_minutes,
          status: event.status,
          is_holiday: true,
          classNames: [ "holiday-event" ]
        }
      else
        # 通常のイベント
        # イベントタイプに対応するカテゴリの色を取得
        category = custom_categories.find { |cat| (cat[:id] || cat["id"]) == event.event_type }
        event_color = category ? (category[:color] || category["color"]) : event.display_color

        event_data = {
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
          event_type: event.event_type,
          start_time: event.start_time.iso8601,
          end_time: event.end_time.iso8601,
          reminder_minutes: event.reminder_minutes,
          status: event.status,
          recurring: event.recurring,
          recurring_event_id: event.recurring_event_id
        }

        # 繰り返しイベントの子インスタンスの場合、occurrence_time を追加
        if event.recurring_event_id.present? && event.original_start_time.present?
          event_data[:occurrence_time] = event.original_start_time.iso8601
        elsif event.recurring_event_id.present?
          # original_start_time がない場合は start_time を使用（後方互換性）
          event_data[:occurrence_time] = event.start_time.iso8601
        end

        event_data
      end
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

  # 単一イベントを手動でLINE通知
  def notify_line
    # セキュリティ: 現在のユーザーのイベントのみアクセス可能
    event = @character.events.includes(character: :user).find(params[:id])
    user = event.character&.user

    if user.nil? || user.line_user_id.blank?
      respond_to do |format|
        format.html { redirect_to calendar_index_path(date: event.start_time.to_date), alert: "LINE連携されていないため通知できません。" }
        format.json { render json: { success: false, error: "LINE連携されていないため通知できません。" }, status: :unprocessable_entity }
      end
      return
    end

    category_name = event.display_category_name || "未設定"

    message = <<~TEXT.strip
      🔔 予定が登録されました！

      【カテゴリ】 #{category_name}
      【件名】 #{event.title}
      【開始】 #{event.start_time.strftime("%m月%d日 %H:%M")}
      【終了】 #{event.end_time.strftime("%m月%d日 %H:%M")}

      #{event.description.present? ? "【詳細】\n#{event.description}" : ""}
    TEXT

    success = ::LineBotService.new.send_message(user.line_user_id, message)

    respond_to do |format|
      if success
        format.html { redirect_to calendar_index_path(date: event.start_time.to_date), notice: "LINEへ通知を送信しました。" }
        format.json { render json: { success: true, message: "LINEへ通知を送信しました。" }, status: :ok }
      else
        format.html { redirect_to calendar_index_path(date: event.start_time.to_date), alert: "LINE通知の送信に失敗しました。" }
        format.json { render json: { success: false, error: "LINE通知の送信に失敗しました。" }, status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to calendar_index_path, alert: "イベントが見つかりません。" }
      format.json { render json: { success: false, error: "イベントが見つかりません。" }, status: :not_found }
    end
  rescue LoadError => e
    Rails.logger.error("[Calendar#notify_line] LoadError: #{e.class} - #{e.message}")
    respond_to do |format|
      format.html { redirect_to calendar_index_path, alert: "LINEライブラリの読み込みに失敗しました。" }
      format.json { render json: { success: false, error: "LINEライブラリの読み込みに失敗しました。", details: e.message }, status: :internal_server_error }
    end
  rescue NameError => e
    Rails.logger.error("[Calendar#notify_line] NameError: #{e.class} - #{e.message}")
    respond_to do |format|
      format.html { redirect_to calendar_index_path, alert: "LINE通知中に定数エラーが発生しました。" }
      format.json { render json: { success: false, error: "LINE通知中に定数エラーが発生しました。", details: e.message }, status: :internal_server_error }
    end
  rescue StandardError => e
    Rails.logger.error("[Calendar#notify_line] Error: #{e.class} - #{e.message}")
    respond_to do |format|
      format.html { redirect_to calendar_index_path, alert: "LINE通知の処理中にエラーが発生しました。" }
      format.json { render json: { success: false, error: "LINE通知の処理中にエラーが発生しました。", details: e.message }, status: :internal_server_error }
    end
  end

  private

  # ApplicationController#set_characterを使用（current_user.character）

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

    # 日付検索機能のためのハイライト対象日付
    @highlight_date = params[:highlight_date] ? Date.parse(params[:highlight_date]) : nil
  rescue Date::Error
    @date = Time.zone.today
    @year = @date.year
    @month = @date.month
    @highlight_date = nil
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

    # セキュリティ: 現在のユーザーのキャラクターに紐づくイベントのみ取得
    # 通常のイベントと繰り返しイベントのインスタンスの両方を取得
    # 論理削除されたイベントは除外
    @events = @character.events.active.for_date_range(@start_date, @end_date).to_a

    # 繰り返しイベントの親（マスター）も取得して、表示期間内のインスタンスを追加
    recurring_parents = @character.events.active.recurring_parents.where("start_time <= ?", @end_date)
    recurring_parents.each do |parent|
      occurrences = parent.occurrences_between(@start_date, @end_date)

      # すでに生成されたインスタンス（有効なもの）は含まれているため、重複チェック（日時ベース）
      existing_times = @events.map { |e| [ e.start_time, e.end_time ] }

      # 論理削除された子インスタンスの日時も取得（これらは表示しない）
      cancelled_times = parent.recurring_instances.soft_deleted.map { |e| [ e.start_time, e.end_time ] }

      occurrences.each do |occurrence|
        time_pair = [ occurrence.start_time, occurrence.end_time ]
        # 有効なインスタンスにも論理削除されたインスタンスにも存在しない場合のみ追加
        unless existing_times.include?(time_pair) || cancelled_times.include?(time_pair)
          @events << occurrence
        end
      end
    end

    Rails.logger.info "📅 Found #{@events.count} events (including recurring instances)"

    # 祝日データを取得（設定により表示/非表示切り替え）
    @holidays = @calendar_settings[:show_holidays] ?
                Holiday.where(date: @start_date..@end_date, country: "JP") :
                Holiday.none

    # holidays gemから祝日を取得してイベントリストに追加
    if @calendar_settings[:show_holidays]
      add_holiday_events(@start_date, @end_date)
    end

    Rails.logger.info "📅 Total events with holidays: #{@events.count}"

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
    # セキュリティ: 現在のユーザーのキャラクターに紐づくイベントのみ取得
    # 通常のイベントと繰り返しイベントのインスタンスの両方を取得
    # 論理削除されたイベントは除外
    @events = @character.events.active.for_date_range(@start_date, @end_date).to_a

    # 繰り返しイベントの親（マスター）も取得して、表示期間内のインスタンスを追加
    recurring_parents = @character.events.active.recurring_parents.where("start_time <= ?", @end_date)
    recurring_parents.each do |parent|
      occurrences = parent.occurrences_between(@start_date, @end_date)

      # すでに生成されたインスタンス（有効なもの）は含まれているため、重複チェック（日時ベース）
      existing_times = @events.map { |e| [ e.start_time, e.end_time ] }

      # 論理削除された子インスタンスの日時も取得（これらは表示しない）
      cancelled_times = parent.recurring_instances.soft_deleted.map { |e| [ e.start_time, e.end_time ] }

      occurrences.each do |occurrence|
        time_pair = [ occurrence.start_time, occurrence.end_time ]
        # 有効なインスタンスにも論理削除されたインスタンスにも存在しない場合のみ追加
        unless existing_times.include?(time_pair) || cancelled_times.include?(time_pair)
          @events << occurrence
        end
      end
    end

    # 週表示用の祝日データ取得
    @holidays = @calendar_settings[:show_holidays] ?
                Holiday.where(date: @start_date..@end_date, country: "JP") :
                Holiday.none

    # holidays gemから祝日を取得してイベントリストに追加
    if @calendar_settings[:show_holidays]
      add_holiday_events(@start_date, @end_date)
    end

    @week_days = (@start_date..@end_date).map { |date| date }
  end

  def show_day
    @start_date = @date.beginning_of_day
    @end_date = @date.end_of_day
    # セキュリティ: 現在のユーザーのキャラクターに紐づくイベントのみ取得
    # 論理削除されたイベントは除外
    @events = @character.events.active.for_date_range(@start_date, @end_date)
                   .order(:start_time)

    # 日表示用の祝日データ取得
    @holidays = @calendar_settings[:show_holidays] ?
                Holiday.where(date: @date, country: "JP") :
                Holiday.none

    # holidays gemから祝日を取得してイベントリストに追加
    if @calendar_settings[:show_holidays]
      add_holiday_events(@start_date, @end_date)
    end

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

        # 予定を時間順にソート
        # 1. 終日イベントを先に表示（作成順を維持）
        # 2. その後、時間指定イベントを開始時刻の昇順で表示
        day_events = day_events.sort_by do |event|
          if event.all_day || event.all_day?
            # 終日イベント: 開始時刻を0時として扱い、最初に表示
            [ 0, event.start_time ]
          else
            # 時間指定イベント: 開始時刻の時・分・秒で並び替え
            # 時刻を秒単位の数値に変換して比較
            start_seconds = event.start_time.hour * 3600 + event.start_time.min * 60 + event.start_time.sec
            [ 1, start_seconds, event.start_time ]
          end
        end

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
    # DISABLED: Activity.deadline does not exist
    # この機能はTaskモデルに移行する必要があります
    # アクティビティ（タスク）の期限をカレンダーイベントとして同期する機能
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
                                  :all_day, :event_type, :status, :color, :attendees,
                                  :reminder_minutes,
                                  :start_date_part, :start_hour_part, :start_min_part,
                                  :end_date_part, :end_hour_part, :end_min_part,
                                  :recurring,
                                  recurrence: [ :frequency, :interval, :end_type, :end_date, :count, days_of_week: [] ])
  end

  def normalized_event_attributes
    attrs = event_params.to_h
    all_day = ActiveModel::Type::Boolean.new.cast(attrs["all_day"])

    attrs["start_time"] = normalize_datetime_attribute(
      attrs["start_time"],
      date_part: attrs["start_date_part"],
      hour_part: attrs["start_hour_part"],
      min_part: attrs["start_min_part"],
      fallback: Time.zone.now.beginning_of_hour,
      all_day: all_day,
      ending: false
    )

    attrs["end_time"] = normalize_datetime_attribute(
      attrs["end_time"],
      date_part: attrs["end_date_part"],
      hour_part: attrs["end_hour_part"],
      min_part: attrs["end_min_part"],
      fallback: attrs["start_time"].present? ? coerce_datetime_value(attrs["start_time"]) + 1.hour : Time.zone.now.beginning_of_hour + 1.hour,
      all_day: all_day,
      ending: true
    )

    # 繰り返し関連のパラメータはEvent.newに渡さない（コントローラー側で別途処理）
    attrs.except!("start_date_part", "start_hour_part", "start_min_part", "end_date_part", "end_hour_part", "end_min_part", "recurring", "recurrence")
    attrs
  end

  def normalize_datetime_attribute(value, date_part:, hour_part:, min_part:, fallback:, all_day:, ending:)
    parsed_value = coerce_datetime_value(value)
    return parsed_value if parsed_value.present?

    if date_part.present?
      return build_datetime_from_parts(date_part, hour_part, min_part, all_day: all_day, ending: ending)
    end

    fallback
  end

  def coerce_datetime_value(value)
    return nil if value.blank?

    case value
    when ActiveSupport::TimeWithZone
      value.in_time_zone
    when Time
      value.in_time_zone
    when DateTime
      value.in_time_zone
    when Date
      Time.zone.local(value.year, value.month, value.day)
    when String
      Time.zone.parse(value)
    else
      if value.respond_to?(:to_time)
        value.to_time.in_time_zone
      elsif value.respond_to?(:to_date)
        date = value.to_date
        Time.zone.local(date.year, date.month, date.day)
      end
    end
  rescue ArgumentError, TypeError
    nil
  end

  def build_datetime_from_parts(date_part, hour_part, min_part, all_day:, ending:)
    date =
      case date_part
      when Date
        date_part
      when String
        Date.parse(date_part)
      else
        date_part.to_date
      end

    if all_day
      hour = ending ? 23 : 0
      minute = ending ? 59 : 0
      return Time.zone.local(date.year, date.month, date.day, hour, minute)
    end

    if hour_part.present? && min_part.present?
      return Time.zone.local(date.year, date.month, date.day, hour_part.to_i, min_part.to_i)
    end

    hour = ending ? 23 : 0
    minute = ending ? 59 : 0
    Time.zone.local(date.year, date.month, date.day, hour, minute)
  rescue ArgumentError, TypeError
    nil
  end
  # カレンダー設定関連
  def load_calendar_settings
    Rails.logger.info "📅 Loading calendar settings for character: #{@character&.id}"

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
      Rails.logger.info "📅 Found user calendar settings"
      user_settings = @character.calendar_settings_hash
      # 文字列キーのハッシュをシンボルキーに変換（ただしcustom_categoriesは文字列キーのまま保持）
      user_settings.each do |key, value|
        key_str = key.to_s
        unless key_str == "custom_categories"
          settings[key_str.to_sym] = value
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
    else
      Rails.logger.info "📅 Using default calendar settings"
    end

    Rails.logger.info "📅 Calendar settings loaded successfully"
    settings
  rescue StandardError => e
    # JSON解析エラーの場合はデフォルト設定を返す
    Rails.logger.error "📅 Error loading calendar settings: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
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

  # holidays gemを使って日本の祝日を取得し、@eventsに追加
  def add_holiday_events(start_date, end_date)
    require "holidays"

    # 日本の祝日を取得（:jp リージョン）
    holidays = Holidays.between(start_date, end_date, :jp, :observed)

    Rails.logger.info "🎌 Found #{holidays.count} Japanese holidays between #{start_date} and #{end_date}"

    holidays.each do |holiday|
      # 祝日イベントを作成
      holiday_event = HolidayEvent.new(
        id: "holiday_#{holiday[:date].strftime('%Y%m%d')}_#{holiday[:name].parameterize}",
        title: holiday[:name],
        start_time: Time.zone.local(holiday[:date].year, holiday[:date].month, holiday[:date].day, 0, 0),
        end_time: Time.zone.local(holiday[:date].year, holiday[:date].month, holiday[:date].day, 23, 59),
        all_day: true,
        description: "日本の祝日",
        location: "",
        event_type: "holiday",
        status: "confirmed",
        color: "#DC2626",  # 赤色
        character: @character,
        is_holiday: true,
        category: "holiday",
        reminder_minutes: nil
      )

      @events << holiday_event
      Rails.logger.info "🎌 Added holiday event: #{holiday[:name]} on #{holiday[:date]}"
    end
  rescue LoadError => e
    Rails.logger.error "🎌 Failed to load holidays gem: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "🎌 Error adding holiday events: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
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
