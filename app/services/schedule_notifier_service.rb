# app/services/schedule_notifier_service.rb
# ユーザーの本日・翌日の予定をLINEへ通知するサービス
class ScheduleNotifierService
  def initialize(line_service: LineBotService.new)
    @line_service = line_service
  end

  # 指定ユーザーへ本日・翌日の予定を送信
  # @param user_id [Integer]
  # @return [Boolean]
  def notify_user(user_id)
    user = User.find_by(id: user_id)
    return false unless user
    return false if user.line_user_id.blank?

    schedules = schedules_scope_for(user)
    message = build_message(schedules)

    @line_service.send_message(user.line_user_id, message)
  end

  private

  def schedules_scope_for(user)
    base_scope =
      if user.respond_to?(:schedules)
        user.schedules
      elsif user.respond_to?(:character) && user.character.present?
        Event.where(character: user.character)
      elsif user.respond_to?(:events)
        user.events
      else
        Event.none
      end

    from = Time.zone.today.beginning_of_day
    to = (Time.zone.today + 1.day).end_of_day

    if base_scope.klass.column_names.include?("start_time")
      base_scope.where(start_time: from..to).order(:start_time)
    elsif base_scope.klass.column_names.include?("start_at")
      base_scope.where(start_at: from..to).order(:start_at)
    else
      base_scope.none
    end
  end

  def build_message(schedules)
    today = Time.zone.today
    tomorrow = today + 1.day

    today_items = schedules.select { |item| start_at(item).to_date == today }
    tomorrow_items = schedules.select { |item| start_at(item).to_date == tomorrow }

    <<~TEXT.strip
      📅 予定のお知らせ

      【#{format_date(today)}】
      #{format_items(today_items)}

      【#{format_date(tomorrow)}】
      #{format_items(tomorrow_items)}
    TEXT
  end

  def format_items(items)
    return "予定はありません" if items.empty?

    items.map do |item|
      lines = []
      lines << "・#{format_time_range(item)}"
      lines << "  件名: #{title_for(item)}"
      description = description_for(item)
      lines << "  内容: #{description}" if description.present?
      lines << "  詳細: #{detail_url_for(item)}"
      lines.join("\n")
    end.join("\n")
  end

  def format_date(date)
    date.strftime("%-m月%-d日")
  end

  def format_time_range(item)
    if all_day?(item)
      "#{start_at(item).strftime('%-m月%-d日')} 終日"
    else
      "#{start_at(item).strftime('%-m月%-d日 %H:%M')}〜#{end_at(item).strftime('%H:%M')}"
    end
  end

  def all_day?(item)
    return item.all_day? if item.respond_to?(:all_day?)
    return item.all_day if item.respond_to?(:all_day)

    false
  end

  def title_for(item)
    return item.title if item.respond_to?(:title)
    return item.name if item.respond_to?(:name)

    "(タイトルなし)"
  end

  def description_for(item)
    text =
      if item.respond_to?(:description)
        item.description.to_s.strip
      elsif item.respond_to?(:details)
        item.details.to_s.strip
      else
        ""
      end

    return "" if text.blank? || text.casecmp("null").zero?

    text
  end

  def start_at(item)
    return item.start_time if item.respond_to?(:start_time)
    return item.start_at if item.respond_to?(:start_at)

    raise ArgumentError, "start time field is missing"
  end

  def end_at(item)
    return item.end_time if item.respond_to?(:end_time)
    return item.end_at if item.respond_to?(:end_at)

    start_at(item)
  end

  def detail_url_for(item)
    helpers = Rails.application.routes.url_helpers
    options = { host: default_host, protocol: default_protocol }

    if item.is_a?(Event) && helpers.respond_to?(:calendar_url)
      helpers.calendar_url(item, **options)
    elsif item.class.name == "Schedule" && helpers.respond_to?(:schedule_url)
      helpers.schedule_url(item, **options)
    else
      helpers.polymorphic_url(item, **options)
    end
  rescue
    "URLを生成できませんでした"
  end

  def default_host
    mailer_options = Rails.application.config.action_mailer.default_url_options || {}
    mailer_host = mailer_options[:host]
    mailer_port = mailer_options[:port]
    mailer_host_with_port =
      if mailer_host.present? && mailer_port.present?
        "#{mailer_host}:#{mailer_port}"
      else
        mailer_host
      end

    ENV["APP_HOST"].presence ||
      Rails.application.routes.default_url_options[:host].presence ||
      mailer_host_with_port.presence ||
      "localhost:3000"
  end

  def default_protocol
    ENV["APP_PROTOCOL"].presence || (Rails.env.production? ? "https" : "http")
  end
end
