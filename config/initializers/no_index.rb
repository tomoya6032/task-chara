# 会員制サイトとして検索エンジンのインデックスを防ぐ
# HTTPヘッダーにX-Robots-Tagを追加

Rails.application.config.action_dispatch.default_headers.merge!(
  "X-Robots-Tag" => "noindex, nofollow, noarchive"
)
