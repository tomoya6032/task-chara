# app/services/activity_task_extraction_service.rb
require "openai"

class ActivityTaskExtractionService
  attr_reader :activity, :character

  def initialize(activity:)
    @activity = activity
    @character = activity.character
  end

  def extract_and_create_tasks
    begin
      # 日報内容からタスクを抽出
      extracted_tasks = extract_tasks_from_content
      created_tasks = []

      # 抽出された各タスクを作成
      extracted_tasks.each do |task_data|
        task = create_task_from_extracted_data(task_data)
        created_tasks << task if task.persisted?
      end

      {
        success: true,
        tasks_count: created_tasks.count,
        created_tasks: created_tasks,
        message: "#{created_tasks.count}件のタスク候補を抽出しました（ドラフト状態）。タスク一覧ページで確認・承認してください。"
      }
    rescue => e
      Rails.logger.error "Task extraction failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      {
        success: false,
        error: e.message,
        message: "タスクの抽出に失敗しました"
      }
    end
  end

  private

  def extract_tasks_from_content
    prompt = build_extraction_prompt

    # OpenAI APIを呼び出し
    response = openai_client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: prompt
          },
          {
            role: "user",
            content: "以下の日報内容から予定・タスクを抽出してください：\n\n#{activity.content}"
          }
        ],
        max_tokens: 2000,
        temperature: 0.3,
        response_format: { type: "json_object" }
      }
    )

    # レスポンスを解析
    response_content = response.dig("choices", 0, "message", "content")
    return [] if response_content.blank?

    # JSONをパース
    parsed_response = JSON.parse(response_content)
    extracted_tasks = parsed_response["tasks"] || []

    # 抽出されたタスクの検証とフィルタリング
    extracted_tasks.select do |task|
      task["title"].present? && task["title"].length >= 2
    end
  rescue JSON::ParserError => e
    Rails.logger.error "JSON parsing failed: #{e.message}"
    []
  end

  def build_extraction_prompt
    current_date = Time.current.strftime("%Y年%m月%d日")
    current_time = Time.current.strftime("%H:%M")

    <<~PROMPT
      あなたは日本の日報から予定・タスクを抽出する専門家です。
      日報の内容を分析し、実行可能な具体的なタスクや予定を JSON 形式で抽出してください。

      【抽出対象】
      - 明確な実行予定（例：「明日の10時に〇〇さんを訪問」「来週までに資料作成」）
      - 時間や期限が明記された活動
      - 具体的な作業内容やアクション
      - 会議、訪問、提出期限などの予定

      【除外対象】
      - 抽象的な感想や気持ち（例：「頑張りたい」「良かった」）
      - 既に完了した活動の報告
      - 漠然とした目標や願望
      - 一般論や考察

      【日時の解釈基準】
      - 現在日時: #{current_date} #{current_time}
      - 「明日」→ #{Date.current.tomorrow.strftime("%Y年%m月%d日")}
      - 「来週」→ #{Date.current.next_week.strftime("%Y年%m月%d日")}以降
      - 「今度」「次回」→ #{3.days.from_now.strftime("%Y年%m月%d日")}頃
      - 時間が不明な場合は09:00にデフォルト設定

      【カテゴリ判定】
      - "welfare": 訪問介護、利用者対応、福祉関連
      - "web": Web制作、プログラミング、システム関連
      - "admin": 事務作業、書類作成、会議、報告書

      【嫌悪レベル判定（1-10）】
      - 1-3: 楽しそう、やりがいがありそう、簡単
      - 4-6: 普通、一般的な業務
      - 7-10: 大変そう、複雑、面倒、嫌だと感じられる内容

      以下のJSON形式で回答してください：
      {
        "analysis_summary": "抽出処理の概要",
        "tasks": [
          {
            "title": "タスクのタイトル（2文字以上）",
            "category": "welfare|web|admin",
            "dislike_level": 1-10の数値,
            "due_date": "YYYY-MM-DD HH:MM形式またはnull",
            "extracted_from": "元の文章の該当部分",
            "confidence": 0.0-1.0の信頼度
          }
        ]
      }
    PROMPT
  end

  def create_task_from_extracted_data(task_data)
    # 抽出されたデータからTaskを作成（ドラフト状態）
    task_params = {
      title: task_data["title"]&.strip,
      category: normalize_category(task_data["category"]),
      dislike_level: normalize_dislike_level(task_data["dislike_level"]),
      due_date: parse_due_date(task_data["due_date"]),
      # 抽出タスク関連の情報を設定
      is_draft: true,
      extracted_from_activity_id: activity.id,
      extraction_confidence: task_data["confidence"]&.to_f || 0.8,
      extraction_source_text: task_data["extracted_from"]&.strip
    }

    # バリデーション
    return character.tasks.new unless valid_task_params?(task_params)

    # タスク作成（ドラフト状態）
    task = character.tasks.build(task_params)

    if task.save
      Rails.logger.info "Created draft task: #{task.title} (from activity #{activity.id}) - Index: #{task.extraction_index}"
      task
    else
      Rails.logger.warn "Failed to create draft task: #{task.errors.full_messages.join(', ')}"
      task
    end
  end

  def normalize_category(category)
    case category&.downcase
    when "welfare", "訪問", "福祉", "介護"
      "welfare"
    when "web", "プログラミング", "システム", "開発"
      "web"
    when "admin", "事務", "書類", "会議", "報告"
      "admin"
    else
      "admin" # デフォルト
    end
  end

  def normalize_dislike_level(level)
    level = level.to_i
    return 5 if level < 1 || level > 10
    level
  end

  def parse_due_date(date_string)
    return nil if date_string.blank? || date_string == "null"

    begin
      # ISO形式での解析を試行
      if date_string.match?(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/)
        DateTime.parse(date_string)
      elsif date_string.match?(/^\d{4}-\d{2}-\d{2}$/)
        Date.parse(date_string).beginning_of_day + 9.hours # 09:00に設定
      else
        nil
      end
    rescue Date::Error, ArgumentError
      nil
    end
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
