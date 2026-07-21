# 繰り返しイベント削除バグの分析

## 問題の症状
- **開発環境**: 繰り返し予定のある日を削除できる ✅
- **本番環境**: 削除できず、同じ予定が作成されてしまう ❌

## 根本原因

### 1. `find_or_create_occurrence!`の問題点

**現在のコード（event.rb:391-430）:**
```ruby
def find_or_create_occurrence!(occurrence_time)
  target_time = occurrence_time.is_a?(String) ? Time.zone.parse(occurrence_time) : occurrence_time
  time_range = (target_time - 1.second)..(target_time + 1.second)
  
  # 既存インスタンスを探す
  instance = recurring_instances.find_by(start_time: time_range)
  
  # 見つからなければ新規作成 ← ここが問題！
  unless instance
    instance = recurring_instances.create!(...)
  end
  
  instance
end
```

**destroyアクションのフロー（calendar_controller.rb:288-365）:**
```ruby
def destroy
  base_event = @character.events.find(params[:id])
  
  if params[:occurrence_time].present?
    occurrence_time = Time.zone.parse(params[:occurrence_time])
    
    if base_event.recurring_parent?
      # 問題: ここで新しいレコードを作成してしまう！
      target_event = base_event.find_or_create_occurrence!(occurrence_time)
    end
  end
  
  case scope
  when "one"
    target_event.soft_delete!  # 作成したばかりのレコードを削除
  end
end
```

### 2. なぜ本番環境でのみ発生するか

**考えられる原因:**

#### A. タイムゾーンの問題
- 開発環境: `Asia/Tokyo`
- 本番環境: `UTC` または異なる設定
- occurrence_timeのパース結果が異なる

#### B. データの存在チェック範囲が狭い
- 検索範囲: `target_time ± 1秒`
- ミリ秒のずれで検索に失敗する可能性

#### C. occurrence_timeのフォーマット問題
- JavaScript: `event.start_time.iso8601` → `"2026-07-22T10:00:00+09:00"`
- 本番環境で`Time.zone.parse`が異なる結果になる可能性

#### D. 既存データの有無
- 開発環境: 既に子インスタンスが作成済み（編集や移動の結果）
- 本番環境: 親イベントのみで子インスタンスが存在しない
- **仮想オカレンスを削除しようとして新規作成してしまう**

## 修正方針

### Option 1: `find_occurrence`メソッドを追加（推奨）
削除時は`create`しない専用メソッドを使用:
```ruby
def find_occurrence(occurrence_time)
  # 検索のみ、作成はしない
end
```

### Option 2: destroyアクションのロジック修正
occurrence_timeがあっても、既存インスタンスがなければ**キャンセルダミーを作成**:
```ruby
if base_event.recurring_parent?
  existing = base_event.recurring_instances.find_by(start_time: time_range)
  
  if existing
    target_event = existing
  else
    # 仮想オカレンスの削除 → キャンセルダミーを直接作成
    target_event = base_event.recurring_instances.create!(..., cancelled_at: Time.current)
  end
end
```

### Option 3: 検索範囲を拡大
```ruby
time_range = (target_time - 1.minute)..(target_time + 1.minute)
```

## 推奨する修正

**1. `find_occurrence`メソッドの追加**
**2. destroyアクションで`find_or_create`を使わない**
**3. タイムゾーンを明示的に処理**
