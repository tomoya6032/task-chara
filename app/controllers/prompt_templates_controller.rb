class PromptTemplatesController < ApplicationController
  before_action :set_character
  before_action :set_prompt_template, only: [ :show, :edit, :update, :destroy, :toggle_active ]

  def index
    @prompt_templates = PromptTemplate.general_or_organization(@organization&.id)
                                      .includes(:organization)
                                      .order(:meeting_type, :prompt_type, :name)

    # フィルタリング
    @prompt_templates = @prompt_templates.by_meeting_type(params[:meeting_type]) if params[:meeting_type].present?
    @prompt_templates = @prompt_templates.by_prompt_type(params[:prompt_type]) if params[:prompt_type].present?
    @prompt_templates = @prompt_templates.active if params[:active_only] == "true"
  end

  def show
  end

  def new
    @prompt_template = PromptTemplate.new
    # デフォルト値の設定
    @prompt_template.is_active = true
    @prompt_template.meeting_type = params[:meeting_type] if params[:meeting_type].present?
    @prompt_template.prompt_type = params[:prompt_type] if params[:prompt_type].present?
  end

  def create
    @prompt_template = PromptTemplate.new(prompt_template_params)
    @prompt_template.organization_id = @organization&.id

    if @prompt_template.save
      redirect_to @prompt_template, notice: "\u30D7\u30ED\u30F3\u30D7\u30C8\u30C6\u30F3\u30D7\u30EC\u30FC\u30C8\u304C\u6B63\u5E38\u306B\u4F5C\u6210\u3055\u308C\u307E\u3057\u305F\u3002"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @prompt_template.update(prompt_template_params)
      redirect_to @prompt_template, notice: "\u30D7\u30ED\u30F3\u30D7\u30C8\u30C6\u30F3\u30D7\u30EC\u30FC\u30C8\u304C\u6B63\u5E38\u306B\u66F4\u65B0\u3055\u308C\u307E\u3057\u305F\u3002"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @prompt_template.destroy
    redirect_to prompt_templates_url, notice: "\u30D7\u30ED\u30F3\u30D7\u30C8\u30C6\u30F3\u30D7\u30EC\u30FC\u30C8\u304C\u524A\u9664\u3055\u308C\u307E\u3057\u305F\u3002"
  end

  def toggle_active
    @prompt_template.update!(is_active: !@prompt_template.is_active)
    redirect_to prompt_templates_url, notice: "プロンプトテンプレートを#{@prompt_template.is_active? ? '有効' : '無効'}にしました。"
  end

  def preview
    # プロンプトのプレビュー機能
    @meeting_type = params[:meeting_type] || "support_meeting"
    @prompt_type = params[:prompt_type] || "voice_transcription"
    @sample_text = params[:sample_text] || "\u30B5\u30F3\u30D7\u30EB\u30C6\u30AD\u30B9\u30C8\u3067\u3059"

    @template = PromptTemplate.find_template(
      meeting_type: @meeting_type,
      prompt_type: @prompt_type,
      organization_id: @organization&.id
    )

    @generated_prompt = @template.generate_user_prompt(transcribed_text: @sample_text)

    render :preview, layout: false
  end

  private

  def set_character
    # デモ用: 現在は固定のキャラクターを使用
    @organization = Organization.find_or_create_by(name: "サンプル企業")
    @user = @organization.users.find_or_create_by(email: "demo@example.com")
    @character = @user.character || @user.create_character(
      name: "デモキャラクター",
      shave_level: 20,
      stress_level: 30,
      total_points: 0,
      organization: @organization,
      user: @user
    )
  end

  def set_prompt_template
    @prompt_template = PromptTemplate.find(params[:id])
  end

  def prompt_template_params
    params.require(:prompt_template).permit(:name, :meeting_type, :prompt_type, :system_prompt,
                                           :user_prompt_template, :is_active, :description)
  end
end
