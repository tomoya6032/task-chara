class MeetingMinutePdfGenerator
  def initialize(meeting_minute, controller)
    @meeting_minute = meeting_minute
    @controller = controller
  end

  def render
    # WickedPDFを使用してHTMLからPDFを生成
    # コントローラーのインスタンス変数（@meeting_minute）をテンプレートで使用
    @controller.instance_variable_set(:@meeting_minute, @meeting_minute)

    html = @controller.render_to_string(
      template: "meeting_minutes/pdf_template",
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
      dpi: 96,
      # 日本語フォント対応の追加オプション
      print_media_type: true,
      disable_smart_shrinking: false,
      # デバッグ用（本番環境でエラーが出た場合に詳細を確認）
      log_level: "error"
    )
  end
end
