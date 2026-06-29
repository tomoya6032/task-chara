class PromptTemplate < ApplicationRecord
  # 関連付け
  belongs_to :organization, optional: true

  # 会議タイプ定義（MeetingMinuteと同じ）
  enum :meeting_type, {
    regular_meeting: 0,  # 通常の会議議事録
    medical_visit: 1,    # 診察同行の要約
    general: 2           # 汎用（全タイプに適用）
  }

  # プロンプトタイプ定義
  enum :prompt_type, {
    voice_transcription: 0,  # 音声転写用
    image_ocr: 1,           # 画像OCR用
    content_generation: 2    # コンテンツ生成用
  }

  # バリデーション
  validates :name, presence: true, length: { maximum: 100 }
  validates :system_prompt, presence: true, length: { maximum: 2000 }
  validates :user_prompt_template, presence: true, length: { maximum: 3000 }
  validates :meeting_type, presence: true
  validates :prompt_type, presence: true
  validates :description, length: { maximum: 500 }

  # スコープ
  scope :active, -> { where(is_active: true) }
  scope :by_meeting_type, ->(type) { where(meeting_type: type) }
  scope :by_prompt_type, ->(type) { where(prompt_type: type) }
  scope :by_organization, ->(org_id) { where(organization_id: org_id) }
  scope :general_or_organization, ->(org_id) { where(organization_id: [ nil, org_id ]) }

  # クラスメソッド：適切なプロンプトテンプレートを取得
  def self.find_template(meeting_type:, prompt_type:, organization_id: nil)
    # 1. 組織固有のアクティブなテンプレートを優先
    # 2. 次に汎用のアクティブなテンプレートを検索
    # 3. 最後にデフォルトテンプレートを返す

    # Enum の整数値に変換（文字列の場合）
    meeting_type_value = if meeting_type.is_a?(String) || meeting_type.is_a?(Symbol)
                           meeting_types[meeting_type.to_s]
    else
                           meeting_type
    end
    general_type_value = meeting_types[:general]

    # 不正な meeting_type の場合はデフォルトテンプレートを返す
    if meeting_type_value.nil?
      Rails.logger.warn "Invalid meeting_type: #{meeting_type}, using default template"
      return create_default_template("regular_meeting", prompt_type)
    end

    template = active
                .where(meeting_type: [ meeting_type_value, general_type_value ])
                .where(prompt_type: prompt_type)
                .general_or_organization(organization_id)
                .order(
                  Arel.sql("CASE WHEN organization_id = #{organization_id.to_i} THEN 1 ELSE 2 END"),
                  Arel.sql("CASE WHEN meeting_type = #{meeting_type_value.to_i} THEN 1 ELSE 2 END"),
                  :updated_at
                )
                .first

    template || create_default_template(meeting_type, prompt_type)
  end

  # デフォルトテンプレートを作成
  def self.create_default_template(meeting_type, prompt_type)
    case prompt_type.to_s
    when "voice_transcription"
      create!(
        name: "デフォルト音声転写テンプレート",
        meeting_type: meeting_type,
        prompt_type: prompt_type,
        system_prompt: "あなたは会議議事録作成のプロフェッショナルです。音声から文字起こしされた内容を、元の発言の流れや意味を大切にしながら、読みやすい議事録形式に整理してください。要約しすぎず、可能な限り元の内容を保持しつつ構造化することを重視してください。個人情報や機密情報に該当する可能性のある固有名詞は一般的な表現に置き換えて、プライバシーに配慮してください。\n\n【出力形式の指定】\n・大項目は丸数字（①②③④⑤など）で区切る\n・箇条書きには⚫︎または・を使用する\n・マークダウン記法（##、::、- -など）は使用しない\n・読みやすく、視覚的に整理された形式で出力する",
        user_prompt_template: "以下の音声から転写されたテキストを、会議の流れや発言の意味を大切にしながら議事録として整理してください。元の発言内容をできるだけ活かしつつ、読みやすく構造化してください。\n\n【音声転写内容】\n{transcribed_text}\n\n上記の転写内容を基に、以下の観点で議事録を作成してください。\n\n【出力形式】\n①会議の概要と流れ\n②重要な発言・意見の詳細\n  ⚫︎発言者ごとの主な意見\n  ⚫︎議論のポイント\n③議論された事項\n  ⚫︎検討内容の詳細\n  ⚫︎課題や論点\n④決定事項や合意内容\n  ⚫︎確定した事項\n  ⚫︎合意したポイント\n⑤今後のアクション・課題\n  ⚫︎次回までの対応事項\n  ⚫︎継続検討項目\n\n※大項目は①②③④⑤の丸数字、箇条書きは⚫︎または・を使用してください。\n※マークダウン記法（##、::、- -など）は使用しないでください。\n※要約しすぎず、元の発言の内容と文脈を重視して作成してください。",
        description: "システムデフォルトの音声転写用テンプレート - 音声内容重視",
        is_active: true
      )
    when "image_ocr"
      create!(
        name: "デフォルト画像OCRテンプレート",
        meeting_type: meeting_type,
        prompt_type: prompt_type,
        system_prompt: "あなたは会議議事録作成の専門家です。画像から会議資料やメモ、ホワイトボードの内容を読み取り、元の情報をできるだけ完全に保持しながら、読みやすい議事録形式に整理してください。要約しすぎず、画像に含まれる情報の詳細を活かすことを重視してください。個人情報や機密情報に該当する可能性のある固有名詞は一般的な表現に置き換えて、プライバシーに配慮してください。\n\n【出力形式の指定】\n・大項目は丸数字（①②③④⑤など）で区切る\n・箇条書きには⚫︎または・を使用する\n・マークダウン記法（##、::、- -など）は使用しない\n・読みやすく、視覚的に整理された形式で出力する",
        user_prompt_template: "この画像から会議に関する内容を読み取り、画像に含まれる情報をできるだけ詳細に活かしながら議事録として整理してください。\n\n【出力形式】\n①会議概要\n  ⚫︎画像から読み取れる会議名\n  ⚫︎日時・場所\n  ⚫︎参加者\n②議題・検討事項の詳細\n  ⚫︎主な議題\n  ⚫︎検討内容\n③記載されている意見や発言内容\n  ⚫︎重要な意見\n  ⚫︎議論のポイント\n④決定事項・結論\n  ⚫︎確定した内容\n  ⚫︎合意事項\n⑤今後のアクション・課題\n  ⚫︎対応が必要な事項\n  ⚫︎継続検討項目\n⑥その他の重要な記載事項\n  ⚫︎補足情報\n  ⚫︎特記事項\n\n※大項目は①②③④⑤⑥の丸数字、箇条書きは⚫︎または・を使用してください。\n※マークダウン記法（##、::、- -など）は使用しないでください。\n※画像の情報を要約せず、できるだけ完全に反映させてください。",
        description: "システムデフォルトの画像OCR用テンプレート - 画像内容重視",
        is_active: true
      )
    end
  end

  # プロンプト内容を動的に生成
  def generate_user_prompt(variables = {})
    result = user_prompt_template.dup
    variables.each do |key, value|
      result.gsub!("{#{key}}", value.to_s)
    end
    result
  end

  # 表示用名称
  def meeting_type_display
    case meeting_type
    when "regular_meeting"
      "通常の会議議事録"
    when "medical_visit"
      "診察同行の要約"
    when "general"
      "汎用"
    else
      "不明"
    end
  end

  def prompt_type_display
    case prompt_type
    when "voice_transcription"
      "音声転写"
    when "image_ocr"
      "画像OCR"
    when "content_generation"
      "コンテンツ生成"
    else
      "不明"
    end
  end

  # セレクトボックス用の表示名
  def display_name
    "#{name} [#{meeting_type_display} - #{prompt_type_display}]"
  end
end
