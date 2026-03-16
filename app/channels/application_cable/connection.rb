module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    
    def connect
      # 認証が不要な場合は匿名ユーザーとして接続
      self.current_user = find_verified_user
    end
    
    private
    
    def find_verified_user
      # 簡単な実装：セッションからユーザーを取得
      # 本番環境では適切な認証を実装してください
      "anonymous_user"
    end
  end
end