class AiSecretaryController < ApplicationController
  before_action :set_character
  before_action :set_conversation_id

  def chat
    @conversation_id = params[:conversation_id] || AiChat.generate_conversation_id
    @recent_messages = AiChat.for_conversation(@conversation_id).recent.limit(20)
  end

  def send_message
    message_content = params[:message]&.strip

    if message_content.blank?
      render json: { error: "メッセージが空です" }, status: :unprocessable_entity
      return
    end

    # 文書生成コマンドをチェック
    if document_generation_command?(message_content)
      handle_document_generation(message_content)
      return
    end

    begin
      # ユーザーのメッセージを保存
      user_message = @character.ai_chats.create!(
        conversation_id: @conversation_id,
        role: "user",
        content: message_content
      )

      # 会話履歴を取得（コンテキスト用）
      conversation_history = AiChat.conversation_context(@conversation_id, limit: 10)

      # OpenAI APIでAI秘書の応答を生成
      ai_response = generate_ai_response(conversation_history)

      # AI秘書の応答を保存
      assistant_message = @character.ai_chats.create!(
        conversation_id: @conversation_id,
        role: "assistant",
        content: ai_response[:content],
        tokens_used: ai_response[:tokens_used]
      )

      render json: {
        status: "success",
        user_message: {
          id: user_message.id,
          content: user_message.content,
          created_at: user_message.created_at
        },
        ai_response: {
          id: assistant_message.id,
          content: assistant_message.content,
          created_at: assistant_message.created_at
        }
      }

    rescue => e
      Rails.logger.error "AI Secretary error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      render json: {
        error: "AI秘書からの応答取得に失敗しました: #{e.message}"
      }, status: :internal_server_error
    end
  end

  def conversation_history
    page = params[:page] || 1
    @messages = AiChat.for_conversation(@conversation_id)
                     .recent
                     .page(page)
                     .per(50)

    render json: {
      messages: @messages.map do |msg|
        {
          id: msg.id,
          role: msg.role,
          content: msg.content,
          created_at: msg.created_at,
          tokens_used: msg.tokens_used
        }
      end,
      has_more: @messages.next_page.present?
    }
  end

  private

  def set_character
    # デモ用: 現在は固定のキャラクターを使用
    @character = Character.find(1)
  rescue ActiveRecord::RecordNotFound
    @character = Character.first
    redirect_to root_path, alert: "キャラクターが見つかりません" unless @character
  end

  def set_conversation_id
    @conversation_id = params[:conversation_id] || session[:current_conversation_id] || AiChat.generate_conversation_id
    session[:current_conversation_id] = @conversation_id
  end

  def generate_ai_response(conversation_history)
    client = OpenAI::Client.new

    # システムプロンプト（AI秘書の性格・役割設定）
    system_prompt = build_system_prompt

    # メッセージ履歴を整形
    messages = [
      { role: "system", content: system_prompt }
    ]

    # 過去の会話をコンテキストとして追加
    messages.concat(conversation_history)

    response = client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: messages,
        max_tokens: 1000,
        temperature: 0.7
      }
    )

    content = response.dig("choices", 0, "message", "content")
    tokens_used = response.dig("usage", "total_tokens") || 0

    { content: content, tokens_used: tokens_used }
  end

  def document_generation_command?(message)
    commands = [
      /議事録.*作成|議事録.*生成|議事録にして|会議.*まとめ/,
      /支援記録.*作成|支援記録.*生成|支援記録にして|ケース.*まとめ/,
      /日報.*作成|日報.*生成|日報にして|活動.*まとめ/,
      /報告書.*作成|報告書.*生成|報告書にして/
    ]
    commands.any? { |pattern| message.match?(pattern) }
  end

  def handle_document_generation(message)
    begin
      # 会話履歴を取得
      conversation_history = AiChat.conversation_context(@conversation_id, limit: 20)

      # 文書タイプを判定
      document_type = determine_document_type(message)

      # 文書を生成
      generated_document = generate_document_from_chat(conversation_history, document_type)

      # ユーザーのリクエストを保存
      user_message = @character.ai_chats.create!(
        conversation_id: @conversation_id,
        role: "user",
        content: message
      )

      # AI秘書の応答を保存
      assistant_message = @character.ai_chats.create!(
        conversation_id: @conversation_id,
        role: "assistant",
        content: generated_document[:content],
        tokens_used: generated_document[:tokens_used]
      )

      render json: {
        status: "document_generated",
        document_type: document_type,
        user_message: {
          id: user_message.id,
          content: user_message.content,
          created_at: user_message.created_at
        },
        ai_response: {
          id: assistant_message.id,
          content: assistant_message.content,
          created_at: assistant_message.created_at
        },
        actions: [
          {
            type: "create_meeting_minute",
            label: "議事録として保存",
            url: new_meeting_minute_path,
            method: "GET",
            params: { content: generated_document[:content] }
          },
          {
            type: "create_activity",
            label: "日報として保存",
            url: new_activity_path,
            method: "GET",
            params: { content: generated_document[:content] }
          },
          {
            type: "create_support_report",
            label: "支援記録として保存",
            url: new_support_report_path,
            method: "GET",
            params: { content: generated_document[:content] }
          }
        ]
      }

    rescue => e
      Rails.logger.error "Document generation error: #{e.message}"
      render json: {
        error: "文書生成に失敗しました: #{e.message}"
      }, status: :internal_server_error
    end
  end

  def determine_document_type(message)
    case message
    when /議事録|会議/
      "meeting_minute"
    when /支援記録|ケース/
      "support_report"
    when /日報|活動/
      "activity"
    when /報告書/
      "report"
    else
      "general"
    end
  end

  def generate_document_from_chat(conversation_history, document_type)
    client = OpenAI::Client.new

    # 文書生成用のシステムプロンプト
    system_prompt = build_document_generation_prompt(document_type)

    # チャット履歴をテキストにまとめる
    chat_context = conversation_history.map do |msg|
      "#{msg[:role] == 'user' ? 'ユーザー' : 'AI秘書'}: #{msg[:content]}"
    end.join("\n\n")

    messages = [
      { role: "system", content: system_prompt },
      { role: "user", content: "以下のチャット履歴を基に#{document_type_label(document_type)}を作成してください：\n\n#{chat_context}" }
    ]

    response = client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: messages,
        max_tokens: 2000,
        temperature: 0.5
      }
    )

    content = response.dig("choices", 0, "message", "content")
    tokens_used = response.dig("usage", "total_tokens") || 0

    { content: content, tokens_used: tokens_used }
  end

  def document_type_label(document_type)
    case document_type
    when "meeting_minute" then "議事録"
    when "support_report" then "支援記録"
    when "activity" then "日報"
    when "report" then "報告書"
    else "文書"
    end
  end

  def build_document_generation_prompt(document_type)
    base_prompt = "あなたは専門的な文書作成のエキスパートです。チャット履歴から関連する情報を抽出し、"

    case document_type
    when "meeting_minute"
      base_prompt + <<~PROMPT
        議事録として適切な形式で整理してください。

        【議事録の構成】
        1. 会議概要（目的、参加者、日時、場所）
        2. 議題・検討事項
        3. 主な発言・意見
        4. 決定事項・合意内容
        5. 今後のアクション・課題
        6. その他特記事項

        チャット履歴から会議に関連する情報を抽出し、不足している情報は適切に推測・補完してください。
      PROMPT
    when "support_report"
      base_prompt + <<~PROMPT
        支援記録として適切な形式で整理してください。

        【支援記録の構成】
        1. 利用者情報（仮名での記載）
        2. 支援内容・サービス提供状況
        3. 利用者の様子・変化
        4. 支援の成果・課題
        5. 今後の支援方針
        6. 特記事項

        個人情報は適切に匿名化し、支援の専門性を重視した記録として作成してください。
      PROMPT
    when "activity"
      base_prompt + <<~PROMPT
        日報として適切な形式で整理してください。

        【日報の構成】
        1. 日付・作業時間
        2. 実施した業務・活動内容
        3. 成果・進捗状況
        4. 課題・問題点
        5. 明日の予定・目標
        6. その他・連絡事項

        業務の振り返りと明日への計画が明確になるよう、実用的な日報として作成してください。
      PROMPT
    else
      base_prompt + "適切な文書形式で整理してください。読みやすく、要点が明確な文書として作成してください。"
    end
  end

  def build_system_prompt
    character_info = @character ? "キャラクター名: #{@character.name}" : ""
    current_date = Time.current.strftime("%Y年%m月%d日 %H:%M")

    <<~PROMPT
      あなたは優秀なAI秘書です。以下の役割を果たしてください：

      【基本情報】
      #{character_info}
      現在日時: #{current_date}

      【あなたの役割】
      1. ユーザーの質問に親切・丁寧に回答する
      2. 議事録、日報、支援報告書作成のサポート
      3. スケジュール管理やタスク管理のアドバイス
      4. 1歩先、2歩先を考えたリマインダーや提案の提供
      5. 業務効率化のための知見共有

      【回答スタイル】
      - 敬語を使用し、親しみやすく専門的な回答
      - 具体的で実用的なアドバイスを提供
      - 必要に応じて関連する機能やリソースを案内
      - 適度な長さで簡潔かつ有用な情報を提供

      【特別な機能】
      - カレンダーやToDoリストとの連携情報提供
      - 過去の資料や会話履歴を参考にした提案
      - 業務フローの最適化提案

      ユーザーの業務を全力でサポートし、効率的で質の高い仕事ができるよう支援してください。
    PROMPT
  end
end
