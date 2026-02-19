class SpecialActionsController < ApplicationController
  before_action :set_character
  skip_before_action :verify_authenticity_token, only: [ :sauna_activate, :claim_reward ]

  def sauna_activate
    if @character.sauna_available?
      # 強靭さポイントが25以上必要
      if @character.toughness < 25
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update("flash-container",
              partial: "shared/flash_message",
              locals: {
                message: "サウナを利用するには強靭さが25ポイント必要です（現在: #{@character.toughness}）",
                type: "error"
              }
            )
          end
        end
        return
      end

      # サウナ効果を適用（上限チェック付き）と強靭さポイント消費
      @character.inner_peace = [ @character.inner_peace + 15, 100 ].min
      @character.toughness = @character.toughness - 25 + 10  # 25ポイント消費後、10ポイント回復

      begin
        @character.save!
        # 最後にサウナを使った時間を記録
        @character.update!(last_sauna_at: Time.current)

        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.update("character-display",
                partial: "dashboards/character_display",
                locals: { character: @character.reload }
              ),
              turbo_stream.update("status-bars",
                partial: "shared/status_bars",
                locals: { character: @character }
              ),
              turbo_stream.update("action-buttons",
                partial: "shared/action_buttons",
                locals: { character: @character }
              ),
              turbo_stream.update("flash-container",
                partial: "shared/flash_message",
                locals: {
                  message: "🔥 サウナで整いました！内面の穏やかさ+15、精神的強靭さ-25→+10（消費システム導入）",
                  type: "success"
                }
              )
            ]
          end
        end
      rescue => e
        Rails.logger.error "Sauna activation error: #{e.message}"
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update("flash-container",
              partial: "shared/flash_message",
              locals: {
                message: "サウナの利用に失敗しました: #{e.message}",
                type: "error"
              }
            )
          end
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash-container",
            partial: "shared/flash_message",
            locals: {
              message: "サウナを利用するには強靭さが50以上必要で、かつ前回利用から2時間以上経過している必要があります",
              type: "error"
            }
          )
        end
      end
    end
  end

  def claim_reward
    # 強靭さポイントが5以上必要
    if @character.toughness < 5
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash-container",
            partial: "shared/flash_message",
            locals: {
              message: "ご褒美を受け取るには強靭さが5ポイント必要です（現在: #{@character.toughness}）",
              type: "error"
            }
          )
        end
        format.json do
          render json: { success: false, message: "ご褒美を受け取るには強靭さが5ポイント必要です（現在: #{@character.toughness}）" }
        end
      end
      return
    end

    # JSONパラメーターの処理
    if request.content_type == "application/json"
      parsed_params = JSON.parse(request.body.read)
      reward_type = parsed_params["reward_type"]
    else
      reward_type = params[:reward_type]
    end

    # 強靭さポイントを5ポイント消費
    @character.toughness -= 5

    case reward_type
    when "cake"
      @character.inner_peace = [ @character.inner_peace + 5, 100 ].min
      message = "🍰 甘いケーキで心が癒されました！内面の穏やかさ+5（強靭さ-5）"
    when "game"
      @character.intelligence = [ @character.intelligence + 3, 100 ].min
      @character.inner_peace = [ @character.inner_peace + 2, 100 ].min
      message = "🎮 ゲーム時間でリフレッシュ！知性+3、内面の穏やかさ+2（強靭さ-5）"
    when "shopping"
      @character.inner_peace = [ @character.inner_peace + 3, 100 ].min
      message = "🛍️ ショッピングでストレス発散！内面の穏やかさ+3（強靭さ-5）"
    when "movie"
      @character.inner_peace = [ @character.inner_peace + 7, 100 ].min
      message = "🎬 映画鑑賞で感動体験！内面の穏やかさ+7（強靭さ-5）"
    when "nature"
      @character.inner_peace = [ @character.inner_peace + 2, 100 ].min
      @character.intelligence = [ @character.intelligence + 2, 100 ].min
      @character.toughness = [ @character.toughness + 2, 100 ].min
      message = "🌿 自然散歩でバランス良く成長！全ステータス+2（強靭さ-5→+2）"
    when "reading"
      @character.intelligence = [ @character.intelligence + 8, 100 ].min
      message = "📚 読書で知識を蓄積！知性+8（強靭さ-5）"
    else
      @character.inner_peace = [ @character.inner_peace + 3, 100 ].min
      message = "🎁 ご褒美タイムでリフレッシュ！（強靭さ-5）"
    end

    begin
      @character.save!

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update("character-display",
              partial: "dashboards/character_display",
              locals: { character: @character.reload }
            ),
            turbo_stream.update("status-bars",
              partial: "shared/status_bars",
              locals: { character: @character }
            ),
            turbo_stream.update("flash-container",
              partial: "shared/flash_message",
              locals: {
                message: message,
                type: "success"
              }
            )
          ]
        end
        format.json do
          render json: { success: true, message: message }
        end
      end
    rescue => e
      Rails.logger.error "Reward claim error: #{e.message}"
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash-container",
            partial: "shared/flash_message",
            locals: {
              message: "ご褒美の適用に失敗しました: #{e.message}",
              type: "error"
            }
          )
        end
        format.json do
          render json: { success: false, message: "ご褒美の適用に失敗しました: #{e.message}" }
        end
      end
    end
  end

  private

  def set_character
    @organization = Organization.first
    @user = @organization.users.first
    @character = @user.character
  end
end
