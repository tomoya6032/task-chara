# app/channels/ai_processing_channel.rb
class AiProcessingChannel < ApplicationCable::Channel
  def subscribed
    Rails.logger.info "=== AI Processing Channel Subscribed ==="
    Rails.logger.info "Params: #{params.inspect}"
    
    # チャンネルに接続
    activity_id = params[:activity_id]
    if activity_id.present?
      stream_from "ai_processing_#{activity_id}"
      Rails.logger.info "Subscribed to stream: ai_processing_#{activity_id}"
    else
      reject
      Rails.logger.error "Subscription rejected: activity_id missing"
    end
  end

  def unsubscribed
    # チャンネルから切断時のクリーンアップ
    Rails.logger.info "=== AI Processing Channel Unsubscribed ==="
  end
end