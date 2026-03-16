class SupportReportGeneratorService
  def initialize(support_report)
    @support_report = support_report
    @character = support_report.character
    @template = support_report.report_template
    @client = OpenAI::Client.new
  end

  def generate
    return false unless @support_report.draft?

    @support_report.update!(status: :generating, generated_at: Time.current)

    begin
      activities = @support_report.period_activities.order(:created_at)

      if activities.empty?
        @support_report.update!(
          content: "この期間中に記録された活動がありません。",
          status: :completed
        )
        return true
      end

      prompt = build_prompt(activities)
      response = call_openai_api(prompt)

      @support_report.update!(
        content: response,
        status: :completed
      )

      true
    rescue => e
      Rails.logger.error "支援報告書生成エラー: #{e.message}"
      @support_report.update!(status: :error)
      false
    end
  end

  private

  def build_prompt(activities)
    activities_text = activities.map do |activity|
      formatted_activity = []
      formatted_activity << "【投稿日時】#{activity.created_at.strftime('%Y年%m月%d日 %H:%M')}"

      if activity.title.present?
        formatted_activity << "【タイトル】#{activity.title}"
      end

      if activity.category.present?
        category_name = case activity.category
        when "study" then "\u5B66\u7FD2"
        when "work" then "\u4ED5\u4E8B"
        when "exercise" then "\u904B\u52D5"
        when "goal" then "\u76EE\u6A19"
        when "thought" then "\u601D\u8003"
        else "\u305D\u306E\u4ED6"
        end
        formatted_activity << "【カテゴリ】#{category_name}"
      end

      if activity.mood_level.present?
        mood_labels = [ "とても悪い", "悪い", "普通", "良い", "とても良い" ]
        formatted_activity << "【気分】#{mood_labels[activity.mood_level - 1] || '普通'}"
      end

      if activity.fatigue_level.present?
        fatigue_labels = [ "とても疲れた", "疲れた", "普通", "元気", "とても元気" ]
        formatted_activity << "【疲労度】#{fatigue_labels[activity.fatigue_level - 1] || '普通'}"
      end

      if activity.visit_start_time.present? || activity.visit_end_time.present?
        time_info = []
        time_info << activity.visit_start_time.strftime("%H:%M") if activity.visit_start_time
        time_info << activity.visit_end_time.strftime("%H:%M") if activity.visit_end_time
        formatted_activity << "【活動時間】#{time_info.join('〜')}"
      end

      formatted_activity << "【内容】#{activity.content}"

      formatted_activity.join("\n")
    end.join("\n\n" + "="*50 + "\n\n")

    base_prompt = <<~PROMPT
      あなたは福祉施設の支援スタッフです。以下の期間の日報データから、利用者の1ヶ月間の支援報告書を作成してください。

      【対象期間】#{@support_report.period_display}
      【利用者名】#{@character.name}

      【日報データ】
      #{activities_text}

    PROMPT

    format_instructions = if @template&.format_instructions.present?
      <<~FORMAT
        【報告書の書式について】
        以下の書式に従って報告書を作成してください：

        #{@template.format_instructions}

      FORMAT
    else
      <<~FORMAT
        【報告書作成の指針】
        1. 利用者の活動状況の概要をまとめてください
        2. 顕著な変化や成長が見られた点を記載してください
        3. 気分や体調の傾向について分析してください
        4. 今後の支援に向けた提案や注意点を含めてください
        5. 専門的すぎず、わかりやすい文章で作成してください
        6. 1000文字程度で簡潔にまとめてください

      FORMAT
    end

    base_prompt + format_instructions + "報告書を作成してください。"
  end

  def call_openai_api(prompt)
    response = @client.chat(
      parameters: {
        model: "gpt-3.5-turbo",
        messages: [
          {
            role: "system",
            content: "あなたは経験豊富な福祉施設の支援スタッフです。利用者の日報から適切な支援報告書を作成することができます。"
          },
          {
            role: "user",
            content: prompt
          }
        ],
        max_tokens: 2000,
        temperature: 0.7
      }
    )

    response.dig("choices", 0, "message", "content")
  end
end
