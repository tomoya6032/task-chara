class SupportReportsController < ApplicationController
  before_action :set_character
  before_action :set_support_report, only: [ :show, :edit, :update, :destroy ]

  def index
    @support_reports = @character.support_reports.recent.page(params[:page]).per(10)
  end

  def show
  end

  def new
    @support_report = @character.support_reports.build
    @available_templates = ReportTemplate.available_for(current_user)
    # AIチャットの会話履歴を取得
    @ai_conversations = get_ai_conversations

    # デフォルトで前月の期間を設定
    last_month_start = 1.month.ago.beginning_of_month.to_date
    last_month_end = 1.month.ago.end_of_month.to_date

    @support_report.period_start = last_month_start
    @support_report.period_end = last_month_end
    @support_report.title = "#{last_month_start.strftime('%Y年%m月')}の支援報告書"
    
    # デフォルトテンプレートを設定
    default_template = @available_templates.find(&:is_default?)
    @support_report.report_template = default_template if default_template
    
    # チャット内容をプリセット用にセット（パラメーターで指定されている場合）
    if params[:from_chat].present?
      @support_report.content = params[:content] if params[:content].present?
    end
  end

  def create
    @support_report = @character.support_reports.build(support_report_params)
    @support_report.status = :draft

    if @support_report.save
      if params[:sync_generate] == 'true' && Rails.env.development?
        # 開発環境での同期生成（デバッグ用）
        service = SupportReportGeneratorService.new(@support_report)
        if service.generate
          redirect_to support_report_path(@support_report), notice: "支援報告書を即座に生成しました。"
        else
          redirect_to support_report_path(@support_report), alert: "支援報告書の生成に失敗しました。"
        end
      else
        # バックグラウンドで報告書を生成
        GenerateSupportReportJob.perform_later(@support_report)
        redirect_to support_report_path(@support_report), notice: "支援報告書の生成を開始しました。"
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @available_templates = ReportTemplate.available_for(current_user)
  end

  def update
    if @support_report.update(support_report_params)
      redirect_to support_report_path(@support_report), notice: "\u652F\u63F4\u5831\u544A\u66F8\u3092\u66F4\u65B0\u3057\u307E\u3057\u305F\u3002"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @support_report.destroy
    redirect_to support_reports_path, notice: "\u652F\u63F4\u5831\u544A\u66F8\u3092\u524A\u9664\u3057\u307E\u3057\u305F\u3002"
  end

  def generate
    @support_report = @character.support_reports.find(params[:id])

    if @support_report.draft? || @support_report.error?
      GenerateSupportReportJob.perform_later(@support_report)
      redirect_to support_report_path(@support_report), notice: "\u652F\u63F4\u5831\u544A\u66F8\u306E\u751F\u6210\u3092\u958B\u59CB\u3057\u307E\u3057\u305F\u3002"
    else
      redirect_to support_report_path(@support_report), alert: "\u73FE\u5728\u751F\u6210\u4E2D\u307E\u305F\u306F\u65E2\u306B\u5B8C\u6210\u3057\u3066\u3044\u307E\u3059\u3002"
    end
  end

  # AIチャット情報から支援記録を生成
  def generate_from_chat
    conversation_id = params[:conversation_id]
    if conversation_id.blank?
      render json: { error: "会話IDが指定されていません" }, status: :bad_request
      return
    end

    begin
      # 会話履歴を取得
      conversation_history = AiChat.conversation_context(conversation_id, limit: 50)
      
      if conversation_history.empty?
        render json: { error: "指定された会話が見つかりません" }, status: :not_found
        return
      end

      # AIを使って支援記録を生成
      generated_content = generate_support_record_from_chat(conversation_history)
      
      render json: {
        success: true,
        content: generated_content,
        message: "AIチャット情報から支援記録を生成しました"
      }

    rescue => e
      Rails.logger.error "Chat to support record generation error: #{e.message}"
      render json: { 
        error: "支援記録生成に失敗しました: #{e.message}" 
      }, status: :internal_server_error
    end
  end

  private

  def current_user
    # デモ用: 現在は固定のユーザーを使用
    @user
  end

  def set_character
    # デモ用: 現在は固定のキャラクターを使用
    @organization = Organization.find_or_create_by(name: "サンプル企業")
    @user = @organization.users.find_or_create_by(email: "demo@example.com")
    @character = @user.character || @user.create_character(
      name: "デモキャラクター",
      shave_level: 20,
      body_shape: 30,
      inner_peace: 40,
      intelligence: 50,
      toughness: 35
    )
  end

  def set_support_report
    @support_report = @character.support_reports.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to support_reports_path, alert: "指定された支援報告書が見つかりません。"
  end

  def support_report_params
    params.require(:support_report).permit(:title, :period_start, :period_end, :content, :report_template_id)
  end

  # AIチャットの会話履歴を取得
  def get_ai_conversations
    # 最近の会話の一意な conversation_id を取得
    conversation_ids = AiChat.where(character: @character)
                             .select(:conversation_id)
                             .distinct
                             .order('MIN(created_at) DESC')
                             .group(:conversation_id)
                             .limit(10)
                             .pluck(:conversation_id)
    
    # 各会話の詳細情報を取得
    conversations = conversation_ids.map do |conv_id|
      messages = AiChat.for_conversation(conv_id).recent.limit(5)
      next if messages.empty?
      
      {
        conversation_id: conv_id,
        created_at: messages.last.created_at,
        preview: truncate_text(messages.first.content, 100),
        message_count: AiChat.for_conversation(conv_id).count,
        last_message_at: messages.first.created_at
      }
    end.compact.sort_by { |conv| conv[:last_message_at] }.reverse
    
    conversations
  end
  
  # AIチャット履歴から支援記録を生成
  def generate_support_record_from_chat(conversation_history)
    client = OpenAI::Client.new
    
    # チャット履歴をテキストに整形
    chat_context = conversation_history.map do |msg|
      role_label = msg[:role] == 'user' ? 'ユーザー' : 'AI秘書'
      "#{role_label}: #{msg[:content]}"
    end.join("\n\n")
    
    # 支援記録生成用プロンプト
    system_prompt = build_support_record_generation_prompt
    
    messages = [
      { role: "system", content: system_prompt },
      { role: "user", content: "以下のAI秘書との会話履歴を基に支援記録を作成してください：\n\n#{chat_context}" }
    ]
    
    response = client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: messages,
        max_tokens: 2000,
        temperature: 0.3
      }
    )
    
    response.dig("choices", 0, "message", "content") || "支援記録の生成に失敗しました。"
  end
  
  # 支援記録生成用システムプロンプト
  def build_support_record_generation_prompt
    <<~PROMPT
      あなたは支援記録作成の専門家です。AI秘書との会話履歴から、支援やケアに関連する情報を抽出し、適切な支援記録形式で整理してください。
      
      【支援記録の構成】
      1. 支援対象者情報
         - 対象者(仮名で記載)
         - 支援サービスの種類
         - 支援期間
         
      2. 支援内容・サービス提供状況
         - 実施した支援内容
         - 提供したサービス
         - 支援の頻度・時間
         
      3. 利用者の様子・変化
         - 初回時の状況
         - 支援中の変化
         - 現在の状況
         
      4. 支援成果・課題
         - 成果や改善点
         - 未達成の課題
         - 今後の改善点
         
      5. 今後の支援方針
         - 継続する支援内容
         - 新たに取り組むべきこと
         - 終了予定や変更点
         
      6. 特記事項
         - 重要な情報
         - 特別なニーズ
         - 関係機関との連携
      
      【注意事項】
      - 個人情報は必ず仮名化し、プライバシーを守ってください
      - 専門性と客観性を重視した記録として作成してください
      - 会話にない情報は推測せず、「（確認中）」等の注釈を入れてください
      - 実用的で継続的な支援に役立つ記録として作成してください
    PROMPT
  end
  
  # テキスト切り詰め用ヘルパー
  def truncate_text(text, length)
    return "" if text.blank?
    text.length > length ? "#{text[0...length]}..." : text
  end
end
