class PromptTemplate < ApplicationRecord
  # 関連付け
  belongs_to :organization, optional: true

  # 会議タイプ定義（MeetingMinuteと同じ）
  enum :meeting_type, {
    support_meeting: 0,      # 利用者支援会議
    professional_meeting: 1, # 専門職団体会議
    general: 2              # 汎用（全タイプに適用）
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

    template = active
                .where(meeting_type: [ meeting_type, "general" ])
                .where(prompt_type: prompt_type)
                .general_or_organization(organization_id)
                .order(
                  Arel.sql("CASE WHEN organization_id = #{organization_id.to_i} THEN 1 ELSE 2 END"),
                  Arel.sql("CASE WHEN meeting_type = '#{meeting_type}' THEN 1 ELSE 2 END"),
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
        system_prompt: "あなたは会議議事録作成のプロフェッショナルです。音声から文字起こしされた内容を、元の発言の流れや意味を大切にしながら、読みやすい議事録形式に整理してください。要約しすぎず、可能な限り元の内容を保持しつつ構造化することを重視してください。個人情報や機密情報に該当する可能性のある固有名詞は一般的な表現に置き換えて、プライバシーに配慮してください。",
        user_prompt_template: "以下の音声から転写されたテキストを、会議の流れや発言の意味を大切にしながら議事録として整理してください。元の発言内容をできるだけ活かしつつ、読みやすく構造化してください。\n\n【音声転写内容】\n{transcribed_text}\n\n上記の転写内容を基に、以下の観点で議事録を作成してください：\n\n1. 会議の概要と流れ\n2. 重要な発言・意見の詳細\n3. 議論された事項\n4. 決定事項や合意内容\n5. 今後のアクション・課題\n\n※要約しすぎず、元の発言の内容と文脈を重視して作成してください。",
        description: "システムデフォルトの音声転写用テンプレート - 音声内容重視",
        is_active: true
      )
    when "image_ocr"
      create!(
        name: "デフォルト画像OCRテンプレート",
        meeting_type: meeting_type,
        prompt_type: prompt_type,
        system_prompt: "あなたは会議議事録作成の専門家です。画像から会議資料やメモ、ホワイトボードの内容を読み取り、元の情報をできるだけ完全に保持しながら、読みやすい議事録形式に整理してください。要約しすぎず、画像に含まれる情報の詳細を活かすことを重視してください。個人情報や機密情報に該当する可能性のある固有名詞は一般的な表現に置き換えて、プライバシーに配慮してください。",
        user_prompt_template: "この画像から会議に関する内容を読み取り、画像に含まれる情報をできるだけ詳細に活かしながら議事録として整理してください。\n\n以下の構成で、画像の内容を基に充実した議事録を作成してください：\n\n1. 会議概要（画像から読み取れる会議名、日時、参加者など）\n2. 議題・検討事項の詳細\n3. 記載されている意見や発言内容\n4. 決定事項・結論\n5. 今後のアクション・課題\n6. その他の重要な記載事項\n\n※画像の情報を要約せず、できるだけ完全に反映させてください。",
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
    when "support_meeting"
      "利用者支援会議"
    when "professional_meeting"
      "専門職団体会議"
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
