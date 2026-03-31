# app/channels/ai_processing_channel.rb
class AiProcessingChannel < ApplicationCable::Channel
  def subscribed
    Rails.logger.info "=== AI Processing Channel Subscribed ==="
    Rails.logger.info "Params: #{params.inspect}"

    # activity_id または session_id のいずれかが必要
    activity_id = params[:activity_id]
    session_id = params[:session_id]

    if activity_id.present?
      # 既存の議事録を編集中
      stream_from "ai_processing_#{activity_id}"
      Rails.logger.info "Subscribed to meeting stream: ai_processing_#{activity_id}"
    elsif session_id.present?
      # 新規議事録作成中
      stream_from "ai_processing_session_#{session_id}"
      Rails.logger.info "Subscribed to session stream: ai_processing_session_#{session_id}"
    else
      reject
      Rails.logger.error "Subscription rejected: neither activity_id nor session_id provided"
    end
  end

  def unsubscribed
    # チャンネルから切断時のクリーンアップ
    Rails.logger.info "=== AI Processing Channel Unsubscribed ==="
  end
end
