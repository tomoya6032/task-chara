# 議事録生成サービス
# 音声・画像・テキストから議事録を生成する
class MeetingMinutesGeneratorService
  attr_reader :meeting_minute, :source_content, :source_type

  def initialize(meeting_minute, source_content: nil, source_type: :text)
    @meeting_minute = meeting_minute
    @character = meeting_minute.character
    @source_content = source_content || meeting_minute.content
    @source_type = source_type # :text, :voice_transcription, :image_ocr
    @client = OpenAI::Client.new
  end

  def generate
    return false unless meeting_minute.draft? || meeting_minute.error?

    meeting_minute.update(status: :generating)

    begin
      # プロンプトを生成
      prompt = build_prompt

      # AIに送信して議事録を生成
      generated_content = call_openai_api(prompt)

      # 生成された議事録を保存
      meeting_minute.update!(
        content: generated_content,
        status: :completed,
        generated_at: Time.current
      )

      # Turbo Streamsでリアルタイム更新
      broadcast_meeting_minute_update

      true
    rescue => e
      Rails.logger.error "Failed to generate meeting minutes: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      meeting_minute.update(
        status: :error,
        content: "#{meeting_minute.content}\n\n--- エラー ---\n#{e.message}"
      )

      false
    end
  end

  private

  # プロンプトを構築
  def build_prompt
    base_instruction = get_base_instruction_by_type
    source_context = format_source_content
    meeting_info = format_meeting_info

    <<~PROMPT
      #{base_instruction}

      #{meeting_info}

      【入力情報】
      #{source_context}

      【出力要件】
      - Markdown記号（##、**、*、-、_、`など）は一切使用しないでください
      - 見出しは「【】」で囲むか、数字を使って表現してください（例：1. 会議概要）
      - 強調したい箇所は記号ではなく、文章の表現で強調してください
      - 箇条書きは「・」または数字（1. 2. 3.）を使用してください
      - 大学生にも分かりやすい丁寧な言葉遣いで記述してください
      - 各項目は明確に区切り、読みやすく整形してください
      - 事実に基づいた正確な情報を記載してください
      - プレーンテキストとして自然に読める形式で出力してください
    PROMPT
  end

  # 会議情報をフォーマット
  def format_meeting_info
    info = []
    info << "【会議情報】"
    info << "会議名: #{meeting_minute.title}"
    info << "開催日時: #{meeting_minute.formatted_meeting_date}"
    info << "開催場所: #{meeting_minute.location}" if meeting_minute.location.present?
    info << "参加者: #{meeting_minute.participants}" if meeting_minute.participants.present?
    info.join("\n")
  end

  # 会議タイプに応じた基本指示を取得
  def get_base_instruction_by_type
    case meeting_minute.meeting_type
    when "regular_meeting"
      regular_meeting_instruction
    when "medical_visit"
      medical_visit_instruction
    else
      regular_meeting_instruction # デフォルトは通常会議
    end
  end

  # 通常の会議議事録の生成指示
  def regular_meeting_instruction
    <<~INSTRUCTION
      あなたは会議議事録の作成を支援するアシスタントです。
      以下の入力情報をもとに、通常の会議議事録を作成してください。

      【重要】Markdown記号（##、**、*、-、_など）は一切使用せず、プレーンテキストで出力してください。

      【構成】
      1. 会議の概要
         ・何のための会議だったかを3〜5行程度で分かりやすく記載
         ・会議の目的や背景を明確に

      2. 決定事項・議題の要点
         ・会議で決まったこと、話し合われた要点を整理
         ・箇条書きは「・」を使い、文章形式で記述
         ・重要な決定事項を漏れなく記録

      3. 今後のタスク・次回への宿題
         ・誰が、いつまでに、何をするかを明確に記載
         ・期限が決まっているものは日付も含める
         ・担当者と具体的なアクション項目を明示

      4. 会議の雰囲気
         ・談笑があったか、緊張感があったかなど
         ・会議の空気感を感情豊かに記述
         ・参加者の様子や反応も含める
    INSTRUCTION
  end

  # 診察同行の要約の生成指示
  def medical_visit_instruction
    <<~INSTRUCTION
      あなたは医療・福祉分野における記録作成を支援するアシスタントです。
      以下の入力情報をもとに、診察同行の要約を作成してください。

      【重要】Markdown記号（##、**、*、-、_など）は一切使用せず、プレーンテキストで出力してください。

      【構成】
      1. 本日の受診概要
         ・どこの病院（何科）での受診か
         ・どのような目的の受診・同行だったか
         ・受診日時と診察時間の目安
         ・同行したスタッフや家族

      2. 医師からの説明・診断内容
         ・病状の見立てや診断結果
         ・今後の治療方針や方向性
         ・生活上の注意点やアドバイス
         ・検査結果や数値の説明
         ・医師から伝えられた重要事項

      3. 処方薬の変更・指示
         ・新しく処方された薬
         ・薬の変更内容（増量・減量・中止など）
         ・服薬方法や注意点
         ・次回受診の目安や予約状況

      4. 本人の様子・スタッフの所感
         ・受診中の本人の表情や態度
         ・不安そうな様子や質問の内容
         ・医師の言葉を聞いた時のリアクション
         ・同行スタッフが感じたこと
         ・今後の支援のヒントや気づき
         ・温かみのある文章で記述
    INSTRUCTION
  end

  # ソースコンテンツをフォーマット
  def format_source_content
    return "（入力情報がありません）" if source_content.blank?

    case source_type
    when :voice_transcription
      "【音声文字起こし結果】\n#{source_content}"
    when :image_ocr
      "【画像OCR結果】\n#{source_content}"
    when :text
      "【入力テキスト】\n#{source_content}"
    else
      source_content
    end
  end

  # AIサービスを呼び出し
  def call_openai_api(prompt)
    # カスタムプロンプトテンプレートが指定されている場合はそれを使用
    if meeting_minute.prompt_template.present?
      custom_prompt = meeting_minute.prompt_template.content
      final_prompt = "#{custom_prompt}\n\n#{prompt}"
    else
      final_prompt = prompt
    end

    # OpenAI APIを呼び出し
    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: "あなたは福祉・医療分野の記録作成を支援する専門的なアシスタントです。正確で分かりやすい文章を作成することに長けています。"
          },
          {
            role: "user",
            content: final_prompt
          }
        ],
        temperature: 0.7,
        max_tokens: 2000
      }
    )

    # レスポンスから生成されたテキストを取得
    generated_text = response.dig("choices", 0, "message", "content")

    if generated_text.blank?
      raise "AIからの応答が空でした"
    end

    generated_text
  end

  # Turbo Streamsでリアルタイム更新をブロードキャスト
  def broadcast_meeting_minute_update
    Turbo::StreamsChannel.broadcast_replace_to(
      meeting_minute,
      target: ActionView::RecordIdentifier.dom_id(meeting_minute, :content),
      partial: "meeting_minutes/content",
      locals: { meeting_minute: meeting_minute }
    )

    Rails.logger.info "Broadcasted meeting minute update for ID: #{meeting_minute.id}"
  rescue => e
    Rails.logger.error "Failed to broadcast meeting minute update: #{e.message}"
  end
end
