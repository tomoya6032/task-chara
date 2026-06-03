class SupportReportGeneratorService
  def initialize(support_report, activity_ids: nil)
    @support_report = support_report
    @character = support_report.character
    @template = support_report.report_template
    @activity_ids = Array(activity_ids).map(&:to_i).uniq
    @client = OpenAI::Client.new
  end

  def generate
    return false unless @support_report.draft?

    @support_report.update!(status: :generating, generated_at: Time.current)

    begin
      activities = if @activity_ids.present?
        @character.activities.where(id: @activity_ids).order(:created_at)
      else
        @support_report.period_activities.order(:created_at)
      end

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

      【出力形式の重要な指示】
      - A4用紙1枚（1200〜1500文字程度）に収まる分量で作成してください。
      - 箇条書きは使用せず、必ず文章形式で記載してください。
      - 「・」「-」「*」などの箇条書き記号は一切使用しないでください。
      - Markdown記法（#、##、**など）も使用しないでください。
      - 段落分けは改行で行い、見出しが必要な場合は「利用者情報:」「支援内容:」のように通常の文章として記載してください。
      - 日報に記載されている具体的なエピソードや様子を盛り込み、支援の実態が伝わる内容にしてください。

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
        1. 利用者の1ヶ月間の活動状況を文章形式で概説してください
        2. 日報に記載されている具体的なエピソード（発言、行動、様子など）を引用して、支援の実態が分かる内容にしてください
        3. 気分や体調の傾向、変化について分析し、具体例とともに記載してください
        4. 顕著な成長や変化が見られた点を、日報の記録を根拠として説明してください
        5. 今後の支援に向けた提案や注意点を含めてください
        6. 専門的すぎず、ご家族や関係者が読んでも分かりやすい文章で作成してください
        7. A4用紙1枚（1200〜1500文字程度）に収まるよう簡潔にまとめてください
        8. 段落構成は自然な文章の流れで、箇条書きは一切使用しないでください

      FORMAT
    end

    base_prompt + format_instructions + "上記ルールを厳守して、箇条書きを一切使わず、日報の具体的な内容を盛り込んだ文章形式の支援報告書を作成してください。"
  end

  def call_openai_api(prompt)
    response = @client.chat(
      parameters: {
        model: "gpt-3.5-turbo",
        messages: [
          {
            role: "system",
            content: "あなたは経験豊富な福祉施設の支援スタッフです。利用者の日報から適切な支援報告書を作成できます。出力は必ず文章形式のプレーンテキストとし、箇条書き（・、-、*）やMarkdown記号（#, ##, **など）は一切使用しないでください。日報の具体的な内容を盛り込み、支援の様子が伝わる報告書を作成してください。"
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
