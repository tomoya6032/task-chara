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
      conversation_history = AiChat.conversation_context(@conversation_id, 10)

      # Web検索が必要かどうかを判定
      web_search_results = nil
      if needs_web_search?(message_content)
        web_search_results = perform_web_search(message_content)
      end

      # OpenAI APIでAI秘書の応答を生成（検索結果も含める）
      ai_response = generate_ai_response_with_search(conversation_history, web_search_results)

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

  rescue ActiveRecord::RecordNotFound => e
    redirect_to root_path, alert: "キャラクターが見つかりません"
  end

  def set_conversation_id
    @conversation_id = params[:conversation_id] || session[:current_conversation_id] || AiChat.generate_conversation_id
    session[:current_conversation_id] = @conversation_id
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
  def generate_ai_response_with_search(conversation_history, search_results = nil)
    client = OpenAI::Client.new

    # システムプロンプト（AI秘書の性格・役割設定）
    system_prompt = build_system_prompt_with_search(search_results)

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

  # 検索結果を含むシステムプロンプトを構築
  def build_system_prompt_with_search(search_results = nil)
    character_info = @character ? "キャラクター名: #{@character.name}" : ""
    current_date = Time.current.strftime("%Y年%m月%d日 %H:%M")

    search_context = ""
    if search_results && search_results[:results].any?
      search_context = <<~SEARCH

        【Web検索結果】
        検索クエリ: "#{search_results[:query]}"
        検索日時: #{search_results[:searched_at].strftime('%Y年%m月%d日 %H:%M')}

        検索結果:
        #{search_results[:results].map.with_index(1) do |result, i|
          "#{i}. #{result[:title]}\n   #{result[:snippet]}\n   URL: #{result[:url]}"
        end.join("\n\n")}

        ※ 上記の検索結果を参考に最新の情報を含めて回答してください。
      SEARCH
    end

    <<~PROMPT
      あなたは親しみやすくて頼りになるAI秘書です。まるで同僚や友達と話すような自然な会話を心がけてください：

      【基本情報】
      #{character_info}
      現在日時: #{current_date}#{search_context}

      【回答の構造と長さ】
      - 聞かれたことに対して「3つのポイント」で回答する
      - 各ポイントは「200文字程度」で簡潔にまとめる
      - 全体の回答は「600文字程度」で、少し超過してもよいので文章を完結させる
      - 文章が途中で切れないよう、考えをしっかりまとめて回答する
      - 壁打ちや相談に使えるよう、返答の最後に関連質問や提案を1つ含める

      【会話スタイル】
      - 親しみやすく自然な口調で話す
      - 敬語は使いつつも、硬すぎない表現にする
      - 箇条書きよりも自然な文章で回答する
      - まるで隣にいる同僚と話しているような感覚
      - ユーザーの感情や状況に共感を示す
      - 必要以上に丁寧すぎず、適度にカジュアルに

      【あなたができること】
      - 日々の業務や悩みについて気軽に相談に乗る
      - 議事録や報告書の作成をお手伝い
      - スケジュールやタスクの整理をサポート
      - ちょっとした質問から専門的な相談まで対応
      - Web検索で最新情報をお調べして共有
      - 仕事の効率化のアイデアを一緒に考える

      【回答のコツ】
      - 「です・ます」調は使うが、堅苦しくならない
      - 「〜ですね」「〜でしょうか」など会話的な表現を使う
      - 適度に相手の気持ちに寄り添う表現を入れる
      - Web検索結果がある時は自然に情報を織り込む
      - 長すぎず、でも十分に役立つ内容にする

      まるで信頼できる同僚と話しているような、リラックスした雰囲気で会話してください。
      でも、必要な時はしっかりとプロフェッショナルなサポートも提供してくださいね。
    PROMPT
  end

  def build_system_prompt
    character_info = @character ? "キャラクター名: #{@character.name}" : ""
    current_date = Time.current.strftime("%Y年%m月%d日 %H:%M")

    <<~PROMPT
      あなたは親しみやすくて頼りになるAI秘書です。まるで同僚や友達と話すような自然な会話を心がけてください：

      【基本情報】
      #{character_info}
      現在日時: #{current_date}

      【回答の構造と長さ】
      - 聞かれたことに対して「3つのポイント」で回答する
      - 各ポイントは「200文字程度」で簡潔にまとめる
      - 全体の回答は「600文字程度」で、少し超過してもよいので文章を完結させる
      - 文章が途中で切れないよう、考えをしっかりまとめて回答する
      - 壁打ちや相談に使えるよう、返答の最後に関連質問や提案を1つ含める

      【会話スタイル】
      - 親しみやすく自然な口調で話す
      - 敬語は使いつつも、硬すぎない表現にする
      - 箇条書きよりも自然な文章で回答する
      - まるで隣にいる同僚と話しているような感覚
      - ユーザーの感情や状況に共感を示す
      - 必要以上に丁寧すぎず、適度にカジュアルに

      【あなたができること】
      - 日々の業務や悩みについて気軽に相談に乗る
      - 議事録や報告書の作成をお手伝い
      - スケジュールやタスクの整理をサポート
      - ちょっとした質問から専門的な相談まで対応
      - 仕事の効率化のアイデアを一緒に考える

      【回答のコツ】
      - 「です・ます」調は使うが、堅苦しくならない
      - 「〜ですね」「〜でしょうか」など会話的な表現を使う
      - 適度に相手の気持ちに寄り添う表現を入れる
      - 長すぎず、でも十分に役立つ内容にする

      まるで信頼できる同僚と話しているような、リラックスした雰囲気で会話してください。
      でも、必要な時はしっかりとプロフェッショナルなサポートも提供してくださいね。
    PROMPT
  end

  # テキスト切り詰め用ヘルパー
  def truncate_text(text, length)
    return "" if text.blank?
    text.length > length ? "#{text[0...length]}..." : text
  end
end
