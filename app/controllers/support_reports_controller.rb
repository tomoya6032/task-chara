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

    # デフォルトで前月の期間を設定
    last_month_start = 1.month.ago.beginning_of_month.to_date
    last_month_end = 1.month.ago.end_of_month.to_date

    @support_report.period_start = last_month_start
    @support_report.period_end = last_month_end
    @support_report.title = "#{last_month_start.strftime('%Y年%m月')}の支援報告書"
    
    # デフォルトテンプレートを設定
    default_template = @available_templates.find(&:is_default?)
    @support_report.report_template = default_template if default_template
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
end
