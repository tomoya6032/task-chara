class DashboardsController < ApplicationController
  def show
    # デモ用のサンプルデータを作成
    @organization = Organization.find_or_create_by(name: "サンプル企業")
    @user = @organization.users.find_or_create_by(email: "demo@example.com")
    @character = @user.character

    # キャラクターが存在しない場合のフォールバック
    unless @character
      @character = @user.create_character(
        name: "デモキャラクター",
        shave_level: rand(0..100),
        body_shape: rand(0..100),
        inner_peace: rand(0..100),
        intelligence: rand(0..100),
        toughness: rand(0..100)
      )
    end
  end
end
