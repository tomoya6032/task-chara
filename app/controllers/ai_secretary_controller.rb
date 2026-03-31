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
