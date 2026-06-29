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
      # 訪問開始日時順（nullの場合は終了日時、それもnullの場合は作成日時）でソート
      activities = if @activity_ids.present?
        @character.activities.where(id: @activity_ids)
                             .order(Arel.sql("COALESCE(visit_start_time, visit_end_time, created_at) ASC"))
      else
        @support_report.period_activities
                       .order(Arel.sql("COALESCE(visit_start_time, visit_end_time, created_at) ASC"))
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
    activities_text = activities.map.with_index(1) do |activity, index|
      formatted_activity = []
      formatted_activity << "■日報ID: #{activity.id}"

      # 訪問開始日時（支援日時）を明確に表示
      if activity.visit_start_time.present?
        formatted_activity << "【実際の訪問開始日時（支援日時）】#{activity.visit_start_time.strftime('%Y/%m/%d %H:%M')}"
      elsif activity.visit_end_time.present?
        # visit_start_timeがない場合はvisit_end_timeを使用
        formatted_activity << "【実際の訪問日時（支援日時）】#{activity.visit_end_time.strftime('%Y/%m/%d %H:%M')}"
      else
        # 訪問日時が設定されていない場合はcreated_atを使用
        formatted_activity << "【実際の訪問日時（支援日時）】#{activity.created_at.strftime('%Y/%m/%d %H:%M')}"
      end

      # データ最終編集日時（参考情報）
      if activity.updated_at != activity.created_at
        formatted_activity << "【データ最終編集日時】#{activity.updated_at.strftime('%Y/%m/%d %H:%M')}"
      end

      if activity.title.present?
        formatted_activity << "【タイトル】#{activity.title}"
      end

      if activity.category.present?
        category_name = case activity.category
        when "study" then "学習"
        when "work" then "仕事"
        when "exercise" then "運動"
        when "goal" then "目標"
        when "thought" then "思考"
        else "その他"
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

      if activity.visit_start_time.present? && activity.visit_end_time.present?
        duration = ((activity.visit_end_time - activity.visit_start_time) / 60).round
        formatted_activity << "【活動時間】#{activity.visit_start_time.strftime('%H:%M')}〜#{activity.visit_end_time.strftime('%H:%M')} (約#{duration}分)"
      elsif activity.visit_start_time.present?
        formatted_activity << "【活動開始時刻】#{activity.visit_start_time.strftime('%H:%M')}"
      elsif activity.visit_end_time.present?
        formatted_activity << "【活動終了時刻】#{activity.visit_end_time.strftime('%H:%M')}"
      end

      formatted_activity << "【支援内容】#{activity.content}"

      formatted_activity.join("\n")
    end.join("\n\n" + "="*50 + "\n\n")

    base_prompt = <<~PROMPT
      # 役割
      あなたは優秀な精神保健福祉士、およびケアマネージャーです。
      提示された「対象期間の日報データ」を元に、指定された「参照テンプレート」の枠組みをベースにしつつ、以下の「最優先フォーマット指示」に厳密に従って【支援報告書】を生成してください。

    PROMPT

    # タイトル指示セクション
    title_section = <<~TITLE
      # 🚨 最優先・出力形式の指示
      - 【1行目のタイトル指定】生成する報告書の【絶対に一番最初の1行目】には、以下のタイトルテキストをそのまま配置してください。見出し記号（# や ■）は付けず、プレーンなテキストとして1行目に出力してください。
      #{'  '}
        書き出しのタイトル ➔ #{@support_report.title}

      - 【2行目の期間指定】タイトルの次の行（2行目）には、以下の対象期間をそのまま配置してください。
      #{'  '}
        対象期間 ➔ 期間：#{@support_report.period_display_short}

      - その後、1行空けて（改行を2回入れて）、本文の内容を開始してください。

    TITLE

    # 最優先フォーマット指示セクション（ユーザーが追記した指示を最優先）
    priority_instructions_section = if @template&.format_instructions.present?
      <<~PRIORITY
        # 🚨 最優先フォーマット指示（ここを最も重視して執筆すること）
        #{@template.format_instructions}

      PRIORITY
    else
      ""
    end

    # 参照テンプレートセクション（PDF解析結果または基本構成）
    template_section = if @template&.content.present?
      <<~TEMPLATE
        # 参照する報告書テンプレート（全体の基本構成・項目枠）
        #{@template.content}

      TEMPLATE
    else
      <<~DEFAULT
        # 参照する報告書テンプレート（全体の基本構成・項目枠）
        ■ 対象期間と利用者情報
        ■ 活動状況の概要
        ■ 気分・体調の傾向
        ■ 特記事項（顕著な変化や成長）
        ■ 今後の支援方針

      DEFAULT
    end

    rules_section = <<~RULES
      # 日時に関する厳格なルール
      - 各日報データには「実際の訪問開始日時（支援日時）」と「データ最終編集日時」の2つが記載されています。
      - 支援報告書に記載する日付や時間（例: 『06/23(木) 08:18』など）は、【絶対に】「実際の訪問開始日時（支援日時）」を基準に抽出・作成してください。
      - 「データ最終編集日時」は、システム上の更新記録に過ぎないため、報告書内の支援日付や時系列の組み立てには【絶対に】使用しないでください。
      - 支援の時系列を表現する際は、必ず「実際の訪問開始日時（支援日時）」を使用し、日報はこの日時順に並んでいることを前提に報告書を作成してください。

      # 厳格な出力ルール・禁止事項（必ず遵守すること）
      - 【1行目タイトルの厳守】報告書の1行目には、上記で指定されたタイトルを【絶対に】そのまま出力してください。見出し記号や装飾は一切付けず、プレーンテキストとして配置してください。
      - 【2行目期間の厳守】報告書の2行目には、上記で指定された対象期間（「期間：YYYY.MM.DD　〜　YYYY.MM.DD」形式）を【絶対に】そのまま出力してください。見出し記号や装飾は一切付けず、指定された形式どおりに配置してください。
      - 【記号の完全禁止】文章の冒頭やタイトル、各セクションの見出しなど、あらゆる場所に「###」や「##」などのMarkdown見出し記号を【絶対に】出力しないでください。章の見出しは「■ 見出し名」のように記述してください。
      - 【指示文のコピー禁止】参照テンプレートや最優先フォーマット指示内に記載されている、AI向けのメタ指示（「###セクション:」「###書式パターン:」「###定型項目:」「###締め:」およびその配下の説明文など）は、システム用の指示です。これらを生成される報告書の本文中に【絶対に】描画（コピペ出力）しないでください。
      - 【不要な記号の排除】見出し（■）の前に、箇条書きのハイフン（- ）やドット（.）を付けないでください。また、見出し全体をカギカッコ「「 」」で囲まないでください。
        （❌ 悪い例: - 「■今後の方針」）
        （⭕️ 正しい例: ■今後の方針）
      - 【ハルシネーションの禁止】提示された日報にない事実を捏造しないでください。
      - 【専門職の言葉遣い】適切で丁寧な言葉遣い（敬体）で記述してください。

    RULES

    activities_section = <<~ACTIVITIES
      # 元データ（対象期間の日報・支援記録の一覧 ※訪問開始日時の古い順に並んでいます）
      対象期間：#{@support_report.period_display}
      利用者名：#{@character.name}

      【重要】各日報に記載されている「実際の訪問開始日時（支援日時）」が、その支援が実施された正確な日時です。

      #{activities_text}

    ACTIVITIES

    output_instruction = <<~OUTPUT
      # 出力（「###」などの記号や、AI向け指示テキストはすべて排除し、完成した本文のみを出力してください）：
      -----------------------------------

    OUTPUT

    base_prompt + title_section + priority_instructions_section + template_section + rules_section + activities_section + output_instruction
  end

  def call_openai_api(prompt)
    response = @client.chat(
      parameters: {
        model: "gpt-3.5-turbo",
        messages: [
          {
            role: "system",
            content: "あなたは経験豊富な精神保健福祉士、およびケアマネージャーです。利用者の日報から適切な支援報告書を作成できます。【最重要】報告書の1行目には、指定されたタイトルを見出し記号なしでそのまま出力し、2行目には対象期間（「期間：YYYY.MM.DD　〜　YYYY.MM.DD」形式）をそのまま出力してください。その後1行空けて本文を開始してください。ユーザーから提示される「🚨 最優先フォーマット指示」を【最も重視】して執筆してください。この指示は基本構成よりも優先されます。【重要】出力時に「###」や「##」などのMarkdown記号を【絶対に】使用しないでください。見出しは「■ 見出し名」の形式で記述してください。また、テンプレート内のAI向け指示文（「###セクション:」など）を本文にコピペしないでください。見出しの前にハイフン（-）やカギカッコ（「」）を付けないでください。箇条書きが必要な場合は数字（1. 2. 3.）を使用してください。【日時の取り扱い】各日報には「実際の訪問開始日時（支援日時）」と「データ最終編集日時」が記載されていますが、報告書に記載する日付や時間は必ず「実際の訪問開始日時（支援日時）」を使用してください。編集日時は使用しないでください。日報の具体的な内容を盛り込み、支援の様子が伝わる報告書を作成してください。"
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
