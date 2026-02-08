# app/services/character_polisher.rb
class CharacterPolisher
  include ActiveModel::Model

  attr_accessor :character, :activity, :task

  def initialize(character:, activity: nil, task: nil)
    @character = character
    @activity = activity
    @task = task
    @client = OpenAI::Client.new
  end

  # 日報から AI 解析してキャラクターを磨き上げ
  def polish_from_activity!
    return false unless activity&.content.present?

    begin
      analysis_result = analyze_activity_content

      if analysis_result
        apply_activity_bonuses(analysis_result)
        save_analysis_log(analysis_result)
        true
      else
        false
      end
    rescue => e
      Rails.logger.error "CharacterPolisher Error: #{e.message}"
      false
    end
  end

  # タスク完了時の磨き上げ
  def polish_from_task_completion!
    return false unless task&.completed_at.present?

    begin
      bonus_multiplier = calculate_task_bonus_multiplier
      apply_task_completion_bonuses(bonus_multiplier)
      true
    rescue => e
      Rails.logger.error "Task completion polish error: #{e.message}"
      false
    end
  end

  # タスク未完了によるペナルティ
  def apply_procrastination_penalty!
    overdue_tasks = character.tasks.where(completed_at: nil)
                              .where("created_at < ?", 24.hours.ago)

    return unless overdue_tasks.exists?

    penalty_factor = [ overdue_tasks.count * 0.5, 5.0 ].min

    character.increment!(:shave_level, penalty_factor)
    character.increment!(:body_shape, penalty_factor * 0.8)

    # 上限チェック
    character.update!(
      shave_level: [ character.shave_level, 100 ].min,
      body_shape: [ character.body_shape, 100 ].min
    )
  end

  private

  def analyze_activity_content
    return nil if Rails.env.test? # テスト環境ではスキップ
    return mock_analysis if ENV["OPENAI_ACCESS_TOKEN"].blank?

    prompt = build_analysis_prompt(activity.content)

    response = @client.chat(
      parameters: {
        model: "gpt-3.5-turbo",
        messages: [ { role: "user", content: prompt } ],
        max_tokens: 500,
        temperature: 0.7
      }
    )

    parse_ai_response(response.dig("choices", 0, "message", "content"))
  end

  def build_analysis_prompt(content)
    <<~PROMPT
      あなたは経験豊富な精神保健福祉士です。以下の業務日報を分析し、
      この人の成長につながる要素を以下の観点で5段階評価してください（1-5点）：

      1. 専門性・技術力（technical_skill）: 専門的な知識や技術の活用度
      2. 共感・内面の成長（empathy_growth）: 対人関係での共感や心の成長
      3. コミュニケーション活力（communication_energy）: 積極的な対話や外向的行動

      日報内容:
      #{content}

      以下のJSONフォーマットで回答してください：
      {
        "technical_skill": 数値(1-5),
        "empathy_growth": 数値(1-5),#{' '}
        "communication_energy": 数値(1-5),
        "analysis_comment": "分析コメント"
      }
    PROMPT
  end

  def parse_ai_response(content)
    return nil unless content

    # JSONの抽出を試行
    json_match = content.match(/\{.*\}/m)
    return nil unless json_match

    JSON.parse(json_match[0]).symbolize_keys
  rescue JSON::ParserError
    nil
  end

  def apply_activity_bonuses(analysis)
    bonuses = calculate_status_bonuses(analysis)

    character.increment!(:intelligence, bonuses[:intelligence])
    character.increment!(:inner_peace, bonuses[:inner_peace])
    character.increment!(:toughness, bonuses[:toughness])

    # 活動によるポジティブな影響で外見も改善
    character.decrement!(:shave_level, bonuses[:appearance_improvement])
    character.decrement!(:body_shape, bonuses[:appearance_improvement])

    # 上限・下限チェック
    apply_status_limits!
  end

  def calculate_status_bonuses(analysis)
    base_bonus = 2.0

    {
      intelligence: (analysis[:technical_skill] || 1) * base_bonus,
      inner_peace: (analysis[:empathy_growth] || 1) * base_bonus,
      toughness: (analysis[:communication_energy] || 1) * base_bonus,
      appearance_improvement: ((analysis[:technical_skill] + analysis[:empathy_growth]) / 2.0) * 0.5
    }
  end

  def calculate_task_bonus_multiplier
    base_multiplier = 1.0
    dislike_bonus = (task.dislike_level || 1) * 0.5

    base_multiplier + dislike_bonus
  end

  def apply_task_completion_bonuses(multiplier)
    base_toughness_bonus = 3.0
    toughness_increase = base_toughness_bonus * multiplier

    character.increment!(:toughness, toughness_increase)

    # タスク完了による達成感で外見も少し改善
    character.decrement!(:shave_level, 1.0)
    character.decrement!(:body_shape, 0.5)

    apply_status_limits!
  end

  def apply_status_limits!
    character.update!(
      intelligence: [ [ character.intelligence, 0 ].max, 100 ].min,
      inner_peace: [ [ character.inner_peace, 0 ].max, 100 ].min,
      toughness: [ [ character.toughness, 0 ].max, 100 ].min,
      shave_level: [ [ character.shave_level, 0 ].max, 100 ].min,
      body_shape: [ [ character.body_shape, 0 ].max, 100 ].min
    )
  end

  def save_analysis_log(analysis_result)
    activity.update!(
      ai_analysis_log: {
        timestamp: Time.current,
        analysis_result: analysis_result,
        bonuses_applied: calculate_status_bonuses(analysis_result),
        ai_model: "gpt-3.5-turbo"
      }
    )
  end

  # デモ・開発用のモック分析
  def mock_analysis
    {
      technical_skill: rand(1..5),
      empathy_growth: rand(1..5),
      communication_energy: rand(1..5),
      analysis_comment: "デモ用の分析結果です"
    }
  end
end
