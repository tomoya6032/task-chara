class AiSecretaryController < ApplicationController
  before_action :set_character
  before_action :set_conversation_id

  def chat
    @conversation_id = params[:conversation_id] || AiChat.generate_conversation_id
    @recent_messages = AiChat.for_conversation(@conversation_id).recent.limit(20)
    @pending_tasks = get_pending_tasks
    @upcoming_events = get_upcoming_events
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
      conversation_history = AiChat.conversation_context(@conversation_id, 10)

      # Web検索が必要かどうかを判定
      web_search_results = nil
      if needs_web_search?(message_content)
        web_search_results = perform_web_search(message_content)
      end

      # DBコンテキストを収集 & モード自動検出
      user_context = build_user_context
      active_mode = detect_active_mode(message_content)

      # カレンダー登録意図の検出と自動登録
      calendar_event_result = nil
      if calendar_create_intent?(message_content)
        calendar_event_result = handle_calendar_creation(message_content)
      end

      # OpenAI APIでAI秘書の応答を生成（検索結果・コンテキスト・モードも含める）
      ai_response = generate_ai_response_with_search(conversation_history, web_search_results, user_context, active_mode, calendar_event_result)

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
        },
        active_mode: active_mode,
        calendar_event: calendar_event_result,
        refresh_sidebar: true,
        conversation_id: @conversation_id
      }

    rescue => e
      Rails.logger.error "AI Secretary error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      render json: {
        error: "AI秘書からの応答取得に失敗しました: #{e.message}"
      }, status: :internal_server_error
    end
  end

  def extract_tasks_from_chat
    conversation_id = params[:conversation_id].presence || @conversation_id
    raw_messages = AiChat.conversation_context(conversation_id, 50)
    conversation_messages = normalize_conversation_messages(raw_messages)

    if conversation_messages.blank?
      append_extraction_result_message(
        conversation_id: conversation_id,
        content: "抽出を実行しましたが、会話履歴が見つからなかったためドラフトは作成されませんでした。"
      )
      redirect_to ai_secretary_chat_path(conversation_id: conversation_id), alert: "会話履歴が見つからないため抽出できませんでした"
      return
    end

    begin
      conversation_text = build_conversation_text(conversation_messages)
      extraction_service = ChatTaskExtractionService.new(
        character: @character,
        conversation_id: conversation_id,
        conversation_text: conversation_text
      )
      result = extraction_service.extract_and_create_tasks

      if result[:success]
        notice_message = if result[:tasks_count].positive?
          "🤖 チャットから#{result[:tasks_count]}件のドラフトタスクを作成しました。タスク一覧で承認してください。"
        else
          "チャットを解析しましたが、具体的な予定・タスク候補は見つかりませんでした"
        end

        append_extraction_result_message(
          conversation_id: conversation_id,
          content: build_extraction_result_text(
            tasks_count: result[:tasks_count],
            created_tasks: result[:created_tasks],
            analyzed_count: conversation_messages.size
          )
        )
        redirect_to ai_secretary_chat_path(conversation_id: conversation_id), notice: notice_message
      else
        append_extraction_result_message(
          conversation_id: conversation_id,
          content: "抽出に失敗しました。エラー: #{result[:message]}"
        )
        redirect_to ai_secretary_chat_path(conversation_id: conversation_id), alert: "抽出に失敗しました: #{result[:message]}"
      end
    rescue => e
      Rails.logger.error "extract_tasks_from_chat error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      append_extraction_result_message(
        conversation_id: conversation_id,
        content: "抽出処理でエラーが発生しました: #{e.message}"
      )
      redirect_to ai_secretary_chat_path(conversation_id: conversation_id), alert: "抽出処理でエラーが発生しました: #{e.message}"
    end
  end

  # カレンダーイベントを直接登録（チャット経由）
  def create_calendar_event
    title      = params[:title]&.strip
    start_time = params[:start_time]
    end_time   = params[:end_time]
    event_type = params[:event_type].presence || "work"
    description = params[:description]&.strip

    if title.blank? || start_time.blank?
      render json: { success: false, error: "タイトルと開始時刻は必須です" }, status: :unprocessable_entity
      return
    end

    begin
      parsed_start = Time.zone.parse(start_time)
      parsed_end   = end_time.present? ? Time.zone.parse(end_time) : parsed_start + 1.hour

      event = Event.new(
        title: title,
        start_time: parsed_start,
        end_time: parsed_end,
        event_type: event_type,
        status: :confirmed,
        description: description,
        character: @character
      )

      if event.save
        render json: {
          success: true,
          event: {
            id: event.id,
            title: event.title,
            start_time: event.start_time.strftime("%Y年%m月%d日 %H:%M"),
            end_time: event.end_time.strftime("%H:%M"),
            calendar_url: "/calendar?date=#{event.start_time.to_date}"
          }
        }
      else
        render json: { success: false, errors: event.errors.full_messages }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "create_calendar_event error: #{e.message}"
      render json: { success: false, error: e.message }, status: :internal_server_error
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

  # 会話履歴の一覧を取得
  def conversation_list
    begin
      Rails.logger.info "💬 Fetching conversation list for character: #{@character&.id}"
      conversations = get_conversation_list
      Rails.logger.info "💬 Found #{conversations.length} conversations"

      render json: {
        conversations: conversations,
        character_id: @character&.id,
        current_conversation_id: @conversation_id
      }
    rescue => e
      Rails.logger.error "❌ Error in conversation_list: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: {
        error: "会話履歴の取得に失敗しました",
        conversations: []
      }, status: 500
    end
  end

  # 新しい会話を開始
  def new_conversation
    new_conversation_id = AiChat.generate_conversation_id
    session[:current_conversation_id] = new_conversation_id

    render json: {
      success: true,
      conversation_id: new_conversation_id,
      redirect_url: ai_secretary_chat_path(conversation_id: new_conversation_id)
    }
  end

  private

  def set_character
    # デモ用: 現在は固定のキャラクターを使用
    @character = Character.find_by(id: 1)

    unless @character
      # デモデータがない場合は作成
      @character = Character.create!(
        name: "AI秘書",
        description: "親しみやすくて頼りになるAIアシスタントです。",
        character_type: "assistant"
      )
      Rails.logger.info "🚀 Created demo character: #{@character.name}"
    end

    Rails.logger.info "👤 Using character: #{@character.name} (ID: #{@character.id})"

  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "キャラクターが見つかりません"
  end

  def set_conversation_id
    @conversation_id = params[:conversation_id] || session[:current_conversation_id] || AiChat.generate_conversation_id
    session[:current_conversation_id] = @conversation_id
  end

  def build_conversation_text(messages)
    messages.map do |msg|
      role = msg[:role]
      content = msg[:content]
      role_label = role.to_s == "assistant" ? "AI" : "ユーザー"
      "#{role_label}: #{content}"
    end.join("\n")
  end

  def normalize_conversation_messages(messages)
    Array(messages).map do |msg|
      if msg.is_a?(Hash)
        {
          role: msg[:role] || msg["role"],
          content: msg[:content] || msg["content"]
        }
      else
        {
          role: msg.try(:role),
          content: msg.try(:content)
        }
      end
    end.select { |m| m[:content].present? }
  end

  def append_extraction_result_message(conversation_id:, content:)
    return if content.blank?

    @character.ai_chats.create!(
      conversation_id: conversation_id,
      role: "assistant",
      content: content
    )
  rescue => e
    Rails.logger.error "append_extraction_result_message error: #{e.message}"
  end

  def build_extraction_result_text(tasks_count:, created_tasks:, analyzed_count:)
    if tasks_count.to_i <= 0
      return <<~TEXT.strip
        抽出結果:
        - 解析した会話メッセージ数: #{analyzed_count}件
        - 作成されたドラフト: 0件

        今回はタスク候補を抽出できませんでした。日時や行動（例: 明日10時に訪問、資料提出）を明示した内容で再実行してください。
      TEXT
    end

    task_lines = Array(created_tasks).first(5).map.with_index(1) do |task, index|
      due_text = task.due_date.present? ? task.due_date.strftime("%Y/%m/%d %H:%M") : "期限未設定"
      "#{index}. #{task.title}（#{due_text}）"
    end.join("\n")

    <<~TEXT.strip
      抽出結果:
      - 解析した会話メッセージ数: #{analyzed_count}件
      - 作成されたドラフト: #{tasks_count}件
      - 保存先: タスク一覧の「承認待ちドラフト」

      作成されたドラフト候補:
      #{task_lines}

      承認すると正式タスクになります（期限付きはカレンダーにも反映されます）。
    TEXT
  end

  # Web検索が必要かどうかを判定
  def needs_web_search?(message)
    search_keywords = [
      /最新.*情報/, /ニュース/, /現在.*状況/, /今.*どう/,
      /調べ/, /検索/, /探し/, /教え.*最新/, /今日.*/, /昨日.*/,
      /株価/, /為替/, /天気/, /予報/, /イベント/, /営業時間/,
      /価格/, /料金/, /費用/, /相場/, /レート/,
      /開いている/, /営業/, /アクセス/, /行き方/, /地図/
    ]

    search_keywords.any? { |pattern| message.match?(pattern) }
  end

  # Web検索を実行
  def perform_web_search(query)
    begin
      # 検索クエリを最適化
      search_query = optimize_search_query(query)

      # Google検索のシミュレーション（実際にはGoogle Custom Search APIやBing Search APIを使用）
      search_results = simulate_web_search(search_query)

      {
        query: search_query,
        results: search_results,
        searched_at: Time.current
      }
    rescue => e
      Rails.logger.error "Web search error: #{e.message}"
      {
        query: query,
        results: [],
        error: "検索中にエラーが発生しました",
        searched_at: Time.current
      }
    end
  end

  # 検索クエリを最適化
  def optimize_search_query(original_query)
    # 日本語の質問文から検索キーワードを抽出
    # 例：「今日の天気はどうですか？」→「今日 天気 予報」
    query = original_query.dup

    # 不要な語句を除去
    remove_words = [ "ですか", "でしょうか", "ください", "教えて", "どう", "はどう", "について" ]
    remove_words.each { |word| query.gsub!(word, "") }

    # 検索に有効な単語を抽出
    query.split.select { |word| word.length > 1 }.join(" ")
  end

  # Web検索のシミュレーション（デモ用）
  def simulate_web_search(query)
    # 実際の実装では、Google Custom Search API、Bing Search API、
    # またはSerpAPIなどの検索エンジンAPIを使用

    sample_results = [
      {
        title: "#{query}に関する最新情報 - 公式サイト",
        url: "https://example.com/info",
        snippet: "#{query}について詳細な情報をご提供しています。最新の情報と正確なデータをお届けします。"
      },
      {
        title: "#{query}の詳細解説 - 専門サイト",
        url: "https://expert.com/details",
        snippet: "専門家による#{query}の解説記事。基礎から応用まで幅広く網羅した内容です。"
      },
      {
        title: "#{query}ガイド - 初心者向け",
        url: "https://guide.com/#{query.downcase}",
        snippet: "#{query}について初心者にもわかりやすく解説。手順やポイントを詳しく説明しています。"
      }
    ]

    # 検索クエリに応じて結果をカスタマイズ
    case query
    when /天気|予報/
      sample_results[0][:title] = "今日の天気予報 - 気象庁"
      sample_results[0][:snippet] = "今日は晴れでしょう。最高気温25度、最低気温15度の予想です。"
    when /株価|為替/
      sample_results[0][:title] = "リアルタイム株価・為替情報 - 金融サイト"
      sample_results[0][:snippet] = "最新の株価情報と為替レートをリアルタイムで提供しています。"
    when /ニュース/
      sample_results[0][:title] = "最新ニュース - 報道サイト"
      sample_results[0][:snippet] = "今日の注目ニュースと最新の出来事をお届けします。"
    end

    sample_results
  end

  # 会話履歴一覧を取得
  def get_conversation_list
    return [] unless @character

    Rails.logger.info "🔍 Total AiChat records for character #{@character.id}: #{AiChat.where(character: @character).count}"

    # 最近の会話の一意な conversation_id を取得
    conversation_ids = AiChat.where(character: @character)
                             .group(:conversation_id)
                             .order("MIN(created_at) DESC")
                             .limit(20)
                             .pluck(:conversation_id)

    Rails.logger.info "🔍 Found conversation IDs: #{conversation_ids}"

    # 各会話の詳細情報を取得
    conversations = conversation_ids.filter_map do |conv_id|
      messages = AiChat.for_conversation(conv_id).recent.limit(1)
      next if messages.empty?

      first_user_message = AiChat.for_conversation(conv_id).where(role: "user").first

      conversation = {
        conversation_id: conv_id,
        title: generate_conversation_title(first_user_message&.content || "新しい会話"),
        preview: truncate_text(messages.first.content, 60),
        last_message_at: messages.first.created_at,
        message_count: AiChat.for_conversation(conv_id).count,
        is_current: conv_id == @conversation_id
      }

      Rails.logger.info "💬 Conversation: #{conversation[:title]} (#{conversation[:message_count]} messages)"
      conversation
    end.sort_by { |conv| conv[:last_message_at] }.reverse

    conversations
  end

  # 会話のタイトルを生成
  def generate_conversation_title(first_message)
    return "新しい会話" if first_message.blank?

    # 最初のメッセージから適切なタイトルを生成
    title = first_message.strip

    # 長すぎる場合は意味のある部分だけを抽出
    if title.length > 30
      # 最初の文や区切りの良い部分で切る
      sentences = title.split(/[。！？\n]/)
      title = sentences.first&.strip || title[0...30]
    end

    # より自然なタイトルに調整
    title = title.gsub(/^(おはよう|こんにちは|こんばんは|すみません|失礼します)[、。！]?/, "") # 挨拶を除去
    title = title.gsub(/について(教えて|聞きたい|質問|相談).*/, "について") # 長い質問を短縮
    title = title.gsub(/を(教えて|聞きたい).*/, "について")
    title = title.gsub(/(です|ます)か？?$/, "") # 敬語の語尾を除去
    title = title.gsub(/(でしょう|だろう)か？?$/, "")
    title = title.gsub(/はどう(です|思います|考えます)か？?$/, "の件")
    title = title.gsub(/について(どう思う|意見|考え).*/, "について")

    # 空白や記号の整理
    title = title.gsub(/\s+/, " ").strip
    title = title.gsub(/^[、。！？\s]+/, "") # 先頭の記号除去

    # 最終的に短くする
    title = truncate_text(title, 25) if title.length > 25

    # 意味のあるタイトルが作れない場合のフォールバック
    if title.blank? || title.length < 3
      time_str = Time.current.strftime("%-m/%-d %H:%M")
      return "#{time_str}の会話"
    end

    title.present? ? title : "新しい会話"
  end

  # 検索結果を含めたAI応答を生成
  def generate_ai_response_with_search(conversation_history, search_results = nil, user_context = {}, active_mode = :secretary, calendar_event_result = nil)
    client = OpenAI::Client.new

    # システムプロンプト（パーソナルエージェント設定）
    system_prompt = build_system_prompt_with_search(search_results, user_context, active_mode)

    # カレンダー登録完了の場合、追加指示をプロンプトに挿入
    if calendar_event_result&.dig(:success)
      ev = calendar_event_result[:event]
      system_prompt += "\n\n【カレンダー登録完了】「#{ev[:title]}」を#{ev[:start_time]}〜#{ev[:end_time]}にカレンダーへ登録しました。応答の中で登録完了を必ず報告し、準備や肥尺・マナーなど追加でサポートすると良いです。"
    elsif calendar_event_result && !calendar_event_result[:success]
      system_prompt += "\n\n【カレンダー登録失敗】登録に失敗しました。お詫びと共に山下の対処方法を提案してください。"
    end

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
        max_tokens: 550,
        temperature: 0.7
      }
    )

    content = response.dig("choices", 0, "message", "content")
    tokens_used = response.dig("usage", "total_tokens") || 0

    { content: content, tokens_used: tokens_used }
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
        max_tokens: 550,
        temperature: 0.7
      }
    )

    content = response.dig("choices", 0, "message", "content")
    tokens_used = response.dig("usage", "total_tokens") || 0

    { content: content, tokens_used: tokens_used }
  end

  # ──────────────────────────────────────────────────────────
  # パーソナル・ビジネスエージェント用システムプロンプト生成
  # ──────────────────────────────────────────────────────────

  def build_system_prompt_with_search(search_results = nil, user_context = {}, active_mode = :secretary)
    current_date = Time.current.strftime("%Y年%m月%d日(%A) %H:%M")

    context_section = build_context_section(user_context)
    search_section  = build_search_section(search_results)
    mode_instruction = build_mode_instruction(active_mode)

    <<~PROMPT
      あなたは篠原様専属の「パーソナル・ビジネスエージェント」です。

      【篠原様のプロフィール】
      - 職業：精神保健福祉士（MHSW）、個人事業主
      - 事業：「みまもりハウス」（訪問福祉サービス）、「ぐんまデザインラボ」（ウェブ制作）
      - 拠点：群馬県前橋市
      - 活動：訪問福祉、群馬DWAT（災害派遣福祉チーム）所属、Rails・WordPressによるウェブ制作
      - 家族：妻、小学生のお子様2人

      【現在日時】#{current_date}

      #{context_section}
      #{search_section}
      【現在のモード】#{mode_instruction}

      【4つの専門性（マルチ・ペルソナ）】
      入力内容に応じて以下の視点を自然に切り替えてください。
      1. 秘書モード：カレンダー・タスク把握、スケジュール調整・リマインド提案
      2. MHSW・訪問福祉相談モード：対人援助技術、福祉制度、前橋市近辺の地域リソース
      3. ビジネス・経営相談モード：freee会計、ウェブ制作（Rails/WordPress）、事業アドバイス
      4. メンタル・疲労管理モード：篠原様の心身健康を気遣い、無理のないサポートを提案

      【能動的（攻め）の行動指針】
      - 会話からタスクを検知した場合は、回答末尾に「→ タスクとして登録しましょうか？」と提案する
      - 直近24〜48時間以内に予定がある場合は「明日は○○の予定ですね。準備は大丈夫ですか？」と気遣いを添える
      - 日報データから特定の訪問先や業務が集中していると見られる場合は「○○の件が増えていますが、ご負担はないですか？」と確認する

      【応答トーン＆マナー】
      - バイステックの7原則（個別化・意図的な感情表出・統制された情緒・受容・非審判的態度・自己決定・秘密保持）に基づいた共感的姿勢
      - 丁寧かつ温かみのあるパートナーとしての口調（硬すぎない敬語）
      - 専門用語は適切に使いつつ、具体的な「次の一手」を必ず提示する
      - 回答は600文字程度。最後に関連する提案・確認を1つ含める
      - Web検索結果がある場合は自然に情報を織り込む
    PROMPT
  end

  def build_system_prompt
    build_system_prompt_with_search
  end

  # DBからユーザーコンテキストを収集
  def build_user_context
    context = {}
    return context unless @character

    begin
      # 今後7日間のイベント
      context[:upcoming_events] = Event.where(character: @character)
                                       .where(start_time: Time.current..(7.days.from_now))
                                       .order(start_time: :asc)
                                       .limit(7)
                                       .map { |e| "#{e.start_time.strftime('%m/%d %H:%M')} #{e.title}" }

      # 未完了タスク（上位10件）
      context[:pending_tasks] = @character.tasks.pending.visible.ordered_by_due_date.limit(10).map do |t|
        due = t.due_date ? " (期限: #{t.due_date.strftime('%m/%d')})".freeze : ""
        "[#{t.category}] #{t.title}#{due}"
      end

      # 最近の日報（3件）
      context[:recent_activities] = @character.activities.recent.limit(3).map do |a|
        "#{a.created_at.strftime('%m/%d')} #{a.title}: #{a.content_summary(length: 80)}"
      end
    rescue => e
      Rails.logger.error "build_user_context error: #{e.message}"
    end

    context
  end

  # 入力内容からモードを自動判定
  def detect_active_mode(message)
    case message
    when /訪問|福祉|支援|相談|利用者|ケース|制度|障害|精神|DWAT|災害|ソーシャルワーク|MSW|地域包括/
      :welfare
    when /会計|freee|請求|売上|経費|確定申告|ウェブ|Rails|WordPress|制作|コード|プログラム|SEO|見積|契約/
      :business
    when /疲れ|休み|体調|しんどい|辛い|しんどい|負担|ストレス|メンタル|気力|睡眠|燃え尽き|バーンアウト/
      :mental
    else
      :secretary
    end
  end

  # コンテキストセクション文字列を生成
  def build_context_section(user_context)
    return "" if user_context.blank?

    lines = []

    if user_context[:upcoming_events].present?
      lines << "【直近の予定（7日間）】"
      lines.concat(user_context[:upcoming_events].map { |e| "  - #{e}" })
    end

    if user_context[:pending_tasks].present?
      lines << "【未完了タスク】"
      lines.concat(user_context[:pending_tasks].map { |t| "  - #{t}" })
    end

    if user_context[:recent_activities].present?
      lines << "【最近の日報（直近3件）】"
      lines.concat(user_context[:recent_activities].map { |a| "  - #{a}" })
    end

    lines.any? ? lines.join("\n") + "\n" : ""
  end

  # 検索結果セクション文字列を生成
  def build_search_section(search_results)
    return "" unless search_results && search_results[:results]&.any?

    lines = [ "【Web検索結果】" ]
    lines << "検索クエリ: \"#{search_results[:query]}\""
    lines << "検索日時: #{search_results[:searched_at].strftime('%Y年%m月%d日 %H:%M')}"
    search_results[:results].each.with_index(1) do |r, i|
      lines << "#{i}. #{r[:title]}"
      lines << "   #{r[:snippet]}"
    end
    lines << "※ 上記の検索結果を参考に最新情報を含めて回答してください。"
    lines.join("\n") + "\n"
  end

  # モード別の指示文を生成
  def build_mode_instruction(mode)
    case mode
    when :welfare
      "【MHSW・訪問福祉相談モード】精神保健福祉士としての専門知識・対人援助技術・前橋市近辺の地域リソースの観点から回答してください。"
    when :business
      "【ビジネス・経営相談モード】個人事業主・ウェブ制作者としての実務的観点（freee、Rails、WordPress等）から具体的なアドバイスをしてください。"
    when :mental
      "【メンタル・疲労管理モード】篠原様の心身の状態を最優先に考え、休息・セルフケア・タスク軽減の観点から温かく寄り添ってください。"
    else
      "【秘書モード】カレンダー・タスク・日報データを踏まえ、スケジュール管理・リマインド・段取り提案を中心に対応してください。"
    end
  end

  # テキスト切り詰め用ヘルパー
  def truncate_text(text, length)
    return "" if text.blank?
    text.length > length ? "#{text[0...length]}..." : text
  end

  # ─────────────────────────────────────────────────────────
  # カレンダー連携: 意図検出 → OpenAI抽出 → イベント登録
  # ─────────────────────────────────────────────────────────

  # カレンダー登録意図の判定
  def calendar_create_intent?(message)
    message.match?(/カレンダー.*入れ|予定.*入れ|カレンダー.*登録|カレンダー.*追加|スケジュール.*入れ|予定.*登録|予定.*追加/)
  end

  # カレンダー登録処理: 抽出 → Event保存
  def handle_calendar_creation(message)
    extracted = extract_event_from_message(message)
    return { success: false, error: "イベント情報を抽出できませんでした" } unless extracted

    event = Event.new(
      title:       extracted[:title],
      start_time:  extracted[:start_time],
      end_time:    extracted[:end_time],
      event_type:  extracted[:event_type] || "work",
      status:      :confirmed,
      description: extracted[:description],
      character:   @character
    )

    if event.save
      Rails.logger.info "📅 Calendar event created: #{event.title} @ #{event.start_time}"
      {
        success: true,
        event: {
          id:           event.id,
          title:        event.title,
          start_time:   event.start_time.strftime("%Y年%m月%d日 %H:%M"),
          end_time:     event.end_time.strftime("%H:%M"),
          calendar_url: "/calendar?date=#{event.start_time.to_date}"
        }
      }
    else
      Rails.logger.error "📅 Calendar event save failed: #{event.errors.full_messages}"
      { success: false, errors: event.errors.full_messages }
    end
  rescue => e
    Rails.logger.error "handle_calendar_creation error: #{e.message}"
    { success: false, error: e.message }
  end

  # OpenAIでメッセージからイベント情報を構造化抽出
  def extract_event_from_message(message)
    client = OpenAI::Client.new
    current_year = Time.current.year

    response = client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: <<~PROMPT
              ユーザーのメッセージからカレンダーイベントの情報を抽出し、必ず次のJSON形式のみを返してください。
              現在年度: #{current_year}年。「m/d」形式は#{current_year}年として解釈してください。

              {
                "title": "イベントのタイトル（相手名+訪問やミーティング等。例: ピカチュウさん 訪問）",
                "start_time": "YYYY-MM-DDTHH:MM:SS+09:00",
                "end_time": "YYYY-MM-DDTHH:MM:SS+09:00（指定なければ開始から1時間後）",
                "event_type": "workまたはpersonalまたはmeeting",
                "description": "補足情報（なければnull）"
              }

              JSONのみ返してください。他のテキストは不要です。
            PROMPT
          },
          { role: "user", content: message }
        ],
        max_tokens: 300,
        temperature: 0.1
      }
    )

    json_text = response.dig("choices", 0, "message", "content")&.strip
    # コードブロックの始まり・終わりを除去
    json_text = json_text.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
    parsed = JSON.parse(json_text, symbolize_names: true)

    {
      title:       parsed[:title],
      start_time:  Time.zone.parse(parsed[:start_time]),
      end_time:    Time.zone.parse(parsed[:end_time]),
      event_type:  parsed[:event_type] || "work",
      description: parsed[:description]
    }
  rescue => e
    Rails.logger.error "extract_event_from_message error: #{e.message} / raw: #{json_text.inspect}"
    nil
  end

  def get_pending_tasks
    return [] unless ActiveRecord::Base.connection.table_exists?("tasks")
    begin
      @character.tasks
                .where(completed_at: nil, hidden: [ false, nil ])
                .order(Arel.sql("due_date IS NULL, due_date ASC"))
                .order(created_at: :desc)
                .limit(20)
    rescue => e
      Rails.logger.error "Error fetching pending tasks: #{e.message}"
      []
    end
  end

  def get_upcoming_events
    return [] unless ActiveRecord::Base.connection.table_exists?("events")
    begin
      Event.where(character: @character)
           .where("start_time >= ?", Time.current.beginning_of_day)
           .where("start_time <= ?", 14.days.from_now)
           .order(start_time: :asc)
           .limit(10)
    rescue => e
      Rails.logger.error "Error fetching upcoming events: #{e.message}"
      []
    end
  end
end
