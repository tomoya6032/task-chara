module ActivitiesHelper
  # 検索パラメータを維持するためのヘルパーメソッド
  def activities_search_params_for_link
    {
      query: params[:query],
      start_date: params[:start_date],
      end_date: params[:end_date],
      sort: params[:sort],
      direction: params[:direction]
    }.compact
  end

  # ソート項目のラベル
  def activities_sort_label(column)
    case column
    when "created_at"
      "作成日"
    when "visit_start_time"
      "支援実施日"
    else
      "作成日"
    end
  end

  # 検索が有効かどうか
  def activities_search_active?
    params[:query].present? || params[:start_date].present? || params[:end_date].present?
  end
end
