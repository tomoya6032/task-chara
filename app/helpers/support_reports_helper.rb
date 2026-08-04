module SupportReportsHelper
  # 検索・ソートパラメータを維持するためのヘルパー
  def search_params_for_link
    {
      keyword: params[:keyword],
      status: params[:status],
      period_start: params[:period_start],
      period_end: params[:period_end],
      sort: params[:sort],
      direction: params[:direction]
    }.compact
  end

  # ソート表示用のラベル
  def sort_label(sort_column, direction)
    column_labels = {
      'created_at' => '作成日',
      'updated_at' => '更新日',
      'period_start' => '期間開始日',
      'period_end' => '期間終了日'
    }
    direction_label = direction == 'asc' ? '古い順' : '新しい順'
    "#{column_labels[sort_column] || sort_column}（#{direction_label}）"
  end

  # 検索が実行されているかチェック
  def search_active?
    params[:keyword].present? || 
    params[:status].present? || 
    params[:period_start].present? || 
    params[:period_end].present?
  end
end
