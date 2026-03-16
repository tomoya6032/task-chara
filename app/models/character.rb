# app/models/character.rb
class Character < ApplicationRecord
  belongs_to :user
  has_many :tasks, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :support_reports, dependent: :destroy

  validates :name, presence: true
  validates :shave_level, :body_shape, :inner_peace, :intelligence, :toughness,
            presence: true,
            numericality: { in: 0..100 }

  # ステータス判定メソッド
  def fat?
    (body_shape || 0) >= 50
  end

  def unshaven?
    (shave_level || 0) >= 50
  end

  # 見た目の状態を返すメソッド
  def body_shape_class
    shape = body_shape || 0
    case shape
    when 0..30
      "w-32 h-32"  # 引き締まった体型
    when 31..60
      "w-40 h-40"  # 普通の体型
    else
      "w-48 h-48"  # ふくよかな体型
    end
  end

  def body_shape_description
    shape = body_shape || 0
    case shape
    when 0..30
      "引き締まっている"
    when 31..60
      "普通"
    else
      "ふくよか"
    end
  end

  def facial_hair_display
    unshaven? ? "🧔‍♂️" : "😊"
  end

  def shave_level_description
    level = shave_level || 0
    case level
    when 0..30
      "清潔感がある"
    when 31..60
      "少し無精髭"
    else
      "しっかり髭"
    end
  end

  # 総合的なキャラクターの状態
  def overall_status
    total_stats = (inner_peace || 0) + (intelligence || 0) + (toughness || 0)
    case total_stats
    when 0..50
      "駆け出し"
    when 51..150
      "成長中"
    when 151..250
      "上級者"
    else
      "マスター"
    end
  end

  # サウナボタンの表示条件（強靭さ50以上かつ前回から2時間以上経過）
  def sauna_available?
    sufficient_toughness = (toughness || 0) >= 50
    time_passed = last_sauna_at.nil? || last_sauna_at < 2.hours.ago
    sufficient_toughness && time_passed
  end

  # 10段階の感情表現
  def emotion_level
    # 総合ステータスから感情レベルを計算（1-10）
    total_positive = (inner_peace || 0) + (intelligence || 0) + (toughness || 0)
    total_negative = (shave_level || 0) + (body_shape || 0)

    # ポジティブ影響を強く、ネガティブ影響を弱く調整
    score = (total_positive * 1.2 - total_negative * 0.8) / 30.0

    [ [ score.round, 1 ].max, 10 ].min
  end

  def emotion_display
    case emotion_level
    when 1
      { emoji: "😭", description: "絶望的", color: "text-red-600" }
    when 2
      { emoji: "😢", description: "落ち込み", color: "text-red-500" }
    when 3
      { emoji: "😟", description: "不安", color: "text-orange-500" }
    when 4
      { emoji: "😐", description: "平凡", color: "text-gray-500" }
    when 5
      { emoji: "🙂", description: "普通", color: "text-gray-600" }
    when 6
      { emoji: "😊", description: "良好", color: "text-blue-500" }
    when 7
      { emoji: "😄", description: "上機嫌", color: "text-green-500" }
    when 8
      { emoji: "😆", description: "絶好調", color: "text-green-600" }
    when 9
      { emoji: "🤩", description: "最高", color: "text-purple-600" }
    when 10
      { emoji: "✨😇✨", description: "超越", color: "text-yellow-500" }
    end
  end

  # 髭エフェクト
  def facial_hair_effect
    level = shave_level || 0
    case level
    when 0..20
      ""
    when 21..50
      "~"
    when 51..80
      "~~"
    else
      "~~~"
    end
  end

  # 体型エフェクト
  def body_scale_effect
    shape = body_shape || 0
    case shape
    when 0..30
      "transform scale-90"
    when 31..60
      "transform scale-100"
    else
      "transform scale-110"
    end
  end

  # 知性エフェクト
  def intelligence_effect
    level = intelligence || 0
    case level
    when 0..40
      { glasses: false, glow: "" }
    when 41..70
      { glasses: true, glow: "filter brightness-110" }
    else
      { glasses: true, glow: "filter brightness-120 drop-shadow-md" }
    end
  end
  def status_color(stat_name)
    value = send(stat_name) || 0
    case value
    when 0..30
      "bg-red-400"
    when 31..70
      "bg-yellow-400"
    else
      "bg-green-400"
    end
  end

  # 知性レベルに応じた表示
  def intelligence_display
    level = intelligence || 0
    case level
    when 0..30
      { emoji: "😐", effect: "" }
    when 31..70
      { emoji: "🤓", effect: "filter: brightness(1.1)" }
    else
      { emoji: "🧠", effect: "filter: brightness(1.2) drop-shadow(0 0 10px gold)" }
    end
  end

  # 内面の平和に応じたエフェクト
  def inner_peace_effect
    level = inner_peace || 0
    case level
    when 0..30
      ""
    when 31..70
      "filter: drop-shadow(0 0 5px rgba(255, 215, 0, 0.3))"
    else
      "filter: drop-shadow(0 0 15px rgba(255, 215, 0, 0.6)) brightness(1.1)"
    end
  end

  # だらしなさ度合いの表示
  def disheveled_level
    shave = shave_level || 0
    body = body_shape || 0
    (shave + body) / 2.0
  end

  # 今日の活動状況
  def todays_summary
    today_activities = activities.today.count
    pending_tasks = tasks.visible.pending.count
    completed_today = tasks.completed.where(completed_at: Time.current.beginning_of_day..Time.current.end_of_day).count

    {
      activities_count: today_activities,
      pending_tasks: pending_tasks,
      completed_tasks: completed_today
    }
  end

  # 連続投稿日数を計算
  def calculate_consecutive_activity_days
    return 0 if activities.empty?

    consecutive_days = 0
    current_date = Date.current

    # 今日から遡って連続している日数を計算
    loop do
      activities_on_date = activities.where(
        created_at: current_date.beginning_of_day..current_date.end_of_day
      )

      if activities_on_date.any?
        consecutive_days += 1
        current_date = current_date.prev_day
      else
        break
      end
    end

    consecutive_days
  end
end
