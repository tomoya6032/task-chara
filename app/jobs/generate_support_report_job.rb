class GenerateSupportReportJob < ApplicationJob
  queue_as :default

  def perform(support_report, activity_ids = nil)
    Rails.logger.info("[GenerateSupportReportJob] start support_report_id=#{support_report.id} status=#{support_report.status} activity_ids_count=#{Array(activity_ids).size}")

    success = SupportReportGeneratorService.new(support_report, activity_ids: activity_ids).generate

    if success
      support_report.reload
      Rails.logger.info("[GenerateSupportReportJob] completed support_report_id=#{support_report.id} status=#{support_report.status} generated_at=#{support_report.generated_at}")
    else
      Rails.logger.error("[GenerateSupportReportJob] failed support_report_id=#{support_report.id} status=#{support_report.status}")
      raise "支援報告書の生成処理が失敗しました"
    end
  rescue => e
    Rails.logger.error "支援報告書生成ジョブエラー: #{e.message}"
    Rails.logger.error "支援報告書生成ジョブエラー詳細: #{e.backtrace&.first(5)&.join("\n")}"
    support_report.update!(status: :error)
    raise
  end
end
