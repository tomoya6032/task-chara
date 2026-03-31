class MeetingMinutesGeneratorService
  def initialize(meeting_minute)
    @meeting_minute = meeting_minute
    @character = meeting_minute.character
    @client = OpenAI::Client.new
  end

  def generate
    return false unless @meeting_minute.draft?

    @meeting_minute.update!(status: :generating, generated_at: Time.current)

    begin
      # 議事録の基本情報から内容を生成
      prompt = build_prompt
      response = call_openai_api(prompt)

      @meeting_minute.update!(
        content: response,
        status: :completed
      )

      # Turbo Streamsでリアルタイム更新
      broadcast_meeting_minute_update

      true
    rescue => e
      Rails.logger.error "会議議事録生成エラー: #{e.message}"
      @meeting_minute.update!(status: :error)
      false
    end
  end

  private

  def build_prompt
    meeting_type_context = case @meeting_minute.meeting_type
    when "support_meeting"
      "利用者支援会議として、利用者の状況把握、支援計画の検討、関係者との連携について議論された"
    when "professional_meeting"
      "専門職団体の会議として、業務改善、研修計画、組織運営について議論された"
    else
      "会議として、重要な議題について議論された"
    end

    base_prompt = <<~PROMPT
      以下の会議情報を基に、適切な議事録を作成してください。

      【会議情報】
      会議名: #{@meeting_minute.title}
      会議種別: #{@meeting_minute.meeting_type_display}
      開催日時: #{@meeting_minute.formatted_meeting_date}
      #{"開催場所: #{@meeting_minute.location}" if @meeting_minute.location.present?}
      #{"参加者: #{@meeting_minute.participants}" if @meeting_minute.participants.present?}

      【背景・文脈】
      #{meeting_type_context}内容です。

      【議事録作成の指針】
      1. 会議の概要と目的を明確にしてください
      2. 議題ごとに整理された内容にしてください
      3. 決定事項と今後のアクションを明確に分けてください
      4. 参加者の発言や意見を適切に要約してください
      5. 次回会議への申し送り事項があれば記載してください
      6. 専門的すぎず、関係者が理解しやすい文章で作成してください

    PROMPT

    format_instructions = get_format_instructions

    base_prompt + format_instructions + "上記の方針に従って、適切な議事録を作成してください。"
  end

  def get_format_instructions
    case @meeting_minute.meeting_type
    when "support_meeting"
      <<~FORMAT

        【利用者支援会議の議事録形式】
        ■ 会議概要
        - 会議名、日時、場所、参加者

        ■ 利用者状況報告
        - 現在の状況
        - 変化や課題

        ■ 検討事項
        - 支援方針の確認・見直し
        - 具体的な支援内容

        ■ 決定事項
        - 合意された支援方針
        - 役割分担

        ■ 今後のアクション
        - 次回までの作業
        - 責任者と期限

        ■ 次回会議予定
        - 日時、議題

      FORMAT
    when "professional_meeting"
      <<~FORMAT

        【専門職団体会議の議事録形式】
        ■ 会議概要
        - 会議名、日時、場所、参加者

        ■ 報告事項
        - 前回からの進捗
        - 現状報告

        ■ 協議事項
        - 検討議題
        - 参加者の意見

        ■ 決定事項
        - 承認された事項
        - 決議内容

        ■ 今後の予定
        - アクションアイテム
        - 責任者と期限

        ■ その他
        - 連絡事項
        - 次回会議予定

      FORMAT
    else
      <<~FORMAT

        【会議議事録の標準形式】
        ■ 会議概要
        ■ 議題・検討事項
        ■ 決定事項
        ■ 今後のアクション
        ■ その他

      FORMAT
    end
  end

  def call_openai_api(prompt)
    response = @client.chat(
      parameters: {
        model: "gpt-3.5-turbo",
        messages: [
          {
            role: "system",
            content: "あなたは経験豊富な事務職員です。会議の内容から適切な議事録を作成することができます。"
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

  # Turbo Streamsでリアルタイム更新をブロードキャスト
  def broadcast_meeting_minute_update
    Turbo::StreamsChannel.broadcast_replace_to(
      @meeting_minute,
      target: ActionView::RecordIdentifier.dom_id(@meeting_minute, :content),
      partial: "meeting_minutes/content",
      locals: { meeting_minute: @meeting_minute }
    )

    Rails.logger.info "Broadcasted meeting minute update for ID: #{@meeting_minute.id}"
  end
end
