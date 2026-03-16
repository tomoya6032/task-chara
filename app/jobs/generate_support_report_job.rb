class GenerateSupportReportJob < ApplicationJob
  queue_as :default

  def perform(support_report)
    SupportReportGeneratorService.new(support_report).generate
  rescue => e
    Rails.logger.error "支援報告書生成ジョブエラー: #{e.message}"
    support_report.update!(status: :error)
    raise
  end
end
