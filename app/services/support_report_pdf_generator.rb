class SupportReportPdfGenerator
  def initialize(support_report, controller)
    @support_report = support_report
    @controller = controller
  end

  def render
    # WickedPDFを使用してHTMLからPDFを生成
    # コントローラーのインスタンス変数（@support_report）をテンプレートで使用
    @controller.instance_variable_set(:@support_report, @support_report)

    html = @controller.render_to_string(
      template: "support_reports/pdf_template",
      layout: false
    )

    WickedPdf.new.pdf_from_string(
      html,
      page_size: "A4",
      margin: {
        top: 20,
        bottom: 20,
        left: 20,
        right: 20
      },
      encoding: "UTF-8",
      enable_local_file_access: true,
      zoom: 1.0,
      dpi: 96
    )
  end
end
