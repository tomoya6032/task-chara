class ReportTemplatesController < ApplicationController
  before_action :set_report_template, only: [:show, :edit, :update, :destroy]

  def index
    @user_templates = ReportTemplate.for_user(current_user_or_nil)
    @system_templates = ReportTemplate.system_wide
  end

  def show
  end

  def new
    @report_template = ReportTemplate.new
  end

  def create
    @report_template = ReportTemplate.new(report_template_params)
    @report_template.user = current_user_or_nil

    if @report_template.save
      @report_template.analyze_pdf_structure!
      redirect_to @report_template, notice: 'テンプレートが作成されました。PDFの構造解析を開始します。'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    unless @report_template.available_for?(current_user_or_nil)
      redirect_to report_templates_path, alert: 'このテンプレートを編集する権限がありません。'
    end
  end

  def update
    unless @report_template.available_for?(current_user_or_nil)
      redirect_to report_templates_path, alert: 'このテンプレートを編集する権限がありません。'
      return
    end

    if @report_template.update(report_template_params)
      # PDFファイルが更新された場合は再解析
      if params[:report_template][:pdf_file].present?
        @report_template.analyze_pdf_structure!
        redirect_to @report_template, notice: 'テンプレートが更新されました。PDFの構造解析を開始します。'
      else
        redirect_to @report_template, notice: 'テンプレートが更新されました。'
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    unless @report_template.available_for?(current_user_or_nil)
      redirect_to report_templates_path, alert: 'このテンプレートを削除する権限がありません。'
      return
    end

    @report_template.destroy
    redirect_to report_templates_path, notice: 'テンプレートが削除されました。'
  end

  def analyze
    @report_template = ReportTemplate.find(params[:id])
    
    unless @report_template.available_for?(current_user_or_nil)
      redirect_to report_templates_path, alert: 'このテンプレートにアクセスする権限がありません。'
      return
    end

    @report_template.analyze_pdf_structure!
    redirect_to @report_template, notice: 'PDFの再解析を開始しました。'
  end

  private

  def set_report_template
    @report_template = ReportTemplate.find(params[:id])
  end

  def report_template_params
    params.require(:report_template).permit(:name, :description, :format_instructions, :is_default, :pdf_file)
  end

  # 認証システムがない場合のダミーメソッド
  def current_user_or_nil
    # TODO: 実際の認証システムに合わせて修正
    nil
  end
end
