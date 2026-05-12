# app/services/chat_task_extraction_service.rb
require "openai"

class ChatTaskExtractionService
  attr_reader :character, :conversation_id, :conversation_text

  def initialize(character:, conversation_id:, conversation_text:)
    @character = character
    @conversation_id = conversation_id
    @conversation_text = conversation_text
  end

  def extract_and_create_tasks
    extracted_tasks = extract_tasks_from_chat
    created_tasks = []

    extracted_tasks.each do |task_data|
      task = create_task_from_extracted_data(task_data)
      created_tasks << task if task.persisted?
    end

    {
      success: true,
      tasks_count: created_tasks.count,
      created_tasks: created_tasks,
      message: "#{created_tasks.count}件のドラフトタスクを作成しました"
    }
  rescue => e
    Rails.logger.error "Chat task extraction failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    {
      success: false,
      error: e.message,
      message: "チャットからのタスク抽出に失敗しました"
    }
  end

  private

  def extract_tasks_from_chat
    response = openai_client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: build_extraction_prompt
          },
          {
            role: "user",
            content: "以下のAI秘書チャット会話から、今後ユーザーが実行すべき予定・タスクを抽出してください。\n\n会話ID: #{conversation_id}\n\n#{conversation_text}"
          }
        ],
        max_tokens: 2200,
        temperature: 0.2,
        response_format: { type: "json_object" }
      }
    )

    response_content = response.dig("choices", 0, "message", "content")
    return [] if response_content.blank?

    parsed = JSON.parse(response_content)
    tasks = parsed["tasks"] || []

    tasks.select { |task| task["title"].present? && task["title"].length >= 2 }
  rescue JSON::ParserError => e
    Rails.logger.error "Chat task JSON parsing failed: #{e.message}"
    []
  end

  def build_extraction_prompt
    current_date = Time.current.strftime("%Y年%m月%d日")
    current_time = Time.current.strftime("%H:%M")

    <<~PROMPT
      あなたはAI秘書チャットの会話から、ユーザーが今後実行するべき予定・タスクを抽出する専門家です。
      会話文脈を読み取り、実行可能な候補のみをJSONで返してください。

      【重要】
      - 既に完了済みの内容は除外
      - 「やる」「対応する」「提出する」「訪問する」「予約する」等の実行アクションを優先
      - 各タスクは「何をするか」を具体的な動詞で記載（例: 申請書を提出する）
      - 期限が推定できる場合は必ず due_date を入れる（例: 会議から1週間以内 → 会議日+7日）
      - 日付・時刻が文中にある場合は必ずdue_dateに反映
      - 「1週間以内」「来週中」「今月末」など相対期限は、現在日時を基準に具体的な日付へ変換してdue_dateに設定
      - 「5/21」「5月21日」など年なし日付は今年の日付として解釈（過去日なら翌年）
      - due_dateは日本時間(JST)として解釈し、"YYYY-MM-DD HH:MM"形式で出力
      - 時間が不明な場合のみ09:00を補完
      - extracted_from には、期限推定の根拠となる原文を入れる

      現在日時: #{current_date} #{current_time}（JST）

      【カテゴリ】
      - welfare: 訪問介護・福祉関連
      - web: Web制作・システム関連
      - admin: 事務・会議・連絡・提出

      以下のJSON形式のみで返してください：
      {
        "analysis_summary": "要約",
        "tasks": [
          {
            "title": "タスク名",
            "category": "welfare|web|admin",
            "dislike_level": 1,
            "due_date": "YYYY-MM-DD HH:MM または null",
            "extracted_from": "根拠となる会話文",
            "confidence": 0.0
          }
        ]
      }
    PROMPT
  end

  def create_task_from_extracted_data(task_data)
    source_text = task_data["extracted_from"].to_s

    task_params = {
      title: task_data["title"]&.strip,
      category: normalize_category(task_data["category"]),
      dislike_level: normalize_dislike_level(task_data["dislike_level"]),
      due_date: parse_due_date(task_data["due_date"], source_text),
      is_draft: true,
      extraction_confidence: task_data["confidence"]&.to_f || 0.8,
      extraction_source_text: source_text.presence,
      description: "AI秘書チャット(会話ID: #{conversation_id})から抽出"
    }

    return character.tasks.new unless valid_task_params?(task_params)

    task = character.tasks.build(task_params)
    task.save
    task
  end

  def normalize_category(category)
    case category&.downcase
    when "welfare", "訪問", "福祉", "介護"
      "welfare"
    when "web", "システム", "開発", "プログラミング"
      "web"
    else
      "admin"
    end
  end

  def normalize_dislike_level(level)
    value = level.to_i
    return 5 if value < 1 || value > 10

    value
  end

  def parse_due_date(date_string, source_text = nil)
    normalized = date_string.to_s.strip

    if normalized.blank? || normalized == "null"
      return parse_relative_due_date_from_text(source_text)
    end

    # よくある相対表現はsource_text優先で補完
    relative_from_source = parse_relative_due_date_from_text(source_text)
    return relative_from_source if relative_from_source.present? && !normalized.match?(/^\d{4}/)

    # 例: 2026-05-21 10:00
    return Time.zone.parse(normalized) if normalized.match?(/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}/)

    # 例: 2026/05/21 10:00
    return Time.zone.parse(normalized.tr("/", "-")) if normalized.match?(/^\d{4}[\/-]\d{2}[\/-]\d{2} \d{2}:\d{2}$/)

    # 例: 5/21 10:00（年なし）
    if normalized.match?(/^\d{1,2}[\/-]\d{1,2}\s+\d{1,2}:\d{2}$/)
      md, hm = normalized.split(/\s+/, 2)
      month_str, day_str = md.split(/[\/-]/)
      hour_str, min_str = hm.split(":")
      return build_year_inferred_time(month_str.to_i, day_str.to_i, hour_str.to_i, min_str.to_i)
    end

    # 例: 5/21（年なし）
    if normalized.match?(/^\d{1,2}[\/-]\d{1,2}$/)
      month_str, day_str = normalized.split(/[\/-]/)
      return build_year_inferred_time(month_str.to_i, day_str.to_i, 9, 0)
    end

    # 例: 2026-05-21（日付のみ）
    if normalized.match?(/^\d{4}[\/-]\d{2}[\/-]\d{2}$/)
      date = Date.strptime(normalized.tr("/", "-"), "%Y-%m-%d")
      return Time.zone.local(date.year, date.month, date.day, 9, 0, 0)
    end

    # 例: 5月21日 / 5月21日 10:00
    if normalized.match?(/^(\d{1,2})月(\d{1,2})日(?:\s*(\d{1,2}):(\d{2}))?$/)
      m = Regexp.last_match(1).to_i
      d = Regexp.last_match(2).to_i
      hh = Regexp.last_match(3)&.to_i || 9
      mm = Regexp.last_match(4)&.to_i || 0
      return build_year_inferred_time(m, d, hh, mm)
    end

    # 最終フォールバック
    Time.zone.parse(normalized)

  rescue Date::Error, ArgumentError
    parse_relative_due_date_from_text(source_text)
  end

  def parse_relative_due_date_from_text(source_text)
    text = source_text.to_s
    return nil if text.blank?

    now = Time.zone.now
    hour, min = extract_time_from_text(text)

    if text.match?(/1週間以内|一週間以内/)
      return now.advance(days: 7).change(hour: hour, min: min)
    end

    if text.match?(/来週中/)
      base = now.to_date.next_week
      return Time.zone.local(base.year, base.month, base.day, hour, min, 0)
    end

    if text.match?(/今月末/)
      base = now.to_date.end_of_month
      return Time.zone.local(base.year, base.month, base.day, hour, min, 0)
    end

    if text.match?(/明日/)
      base = now.to_date.tomorrow
      return Time.zone.local(base.year, base.month, base.day, hour, min, 0)
    end

    if text.match?(/来週/)
      base = now.to_date.next_week
      return Time.zone.local(base.year, base.month, base.day, hour, min, 0)
    end

    nil
  end

  def extract_time_from_text(text)
    if text.match?(/(午前|午後)?\s*(\d{1,2})[:時](\d{2})?/)
      ampm = Regexp.last_match(1)
      hour = Regexp.last_match(2).to_i
      min = Regexp.last_match(3)&.to_i || 0

      if ampm == "午後" && hour < 12
        hour += 12
      elsif ampm == "午前" && hour == 12
        hour = 0
      end

      return [ hour, min ]
    end

    [ 9, 0 ]
  end

  def build_year_inferred_time(month, day, hour, min)
    now = Time.zone.now
    year = now.year
    candidate = Time.zone.local(year, month, day, hour, min, 0)
    candidate = Time.zone.local(year + 1, month, day, hour, min, 0) if candidate < now.beginning_of_day
    candidate
  end

  def valid_task_params?(params)
    params[:title].present? &&
      params[:title].length >= 2 &&
      %w[welfare web admin].include?(params[:category]) &&
      params[:dislike_level].between?(1, 10)
  end

  def openai_client
    @openai_client ||= OpenAI::Client.new
  end
end
