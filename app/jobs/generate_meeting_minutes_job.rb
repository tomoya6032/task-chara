class GenerateMeetingMinutesJob < ApplicationJob
  queue_as :default

  def perform(meeting_minute)
    MeetingMinutesGeneratorService.new(meeting_minute).generate
  rescue => e
    Rails.logger.error "会議議事録生成ジョブエラー: #{e.message}"
    meeting_minute.update!(status: :error)

    # エラー時もブロードキャスト
    broadcast_meeting_minute_error(meeting_minute)

    raise
  end

  private

  def broadcast_meeting_minute_error(meeting_minute)
    Turbo::StreamsChannel.broadcast_replace_to(
      meeting_minute,
      target: ActionView::RecordIdentifier.dom_id(meeting_minute, :content),
      partial: "meeting_minutes/content",
      locals: { meeting_minute: meeting_minute }
    )

    Rails.logger.info "Broadcasted meeting minute error for ID: #{meeting_minute.id}"
  end
end
