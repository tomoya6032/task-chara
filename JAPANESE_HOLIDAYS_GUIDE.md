# 日本の祝日表示機能 実装ガイド

## 📋 概要

カレンダーに日本の祝日を自動的に表示する機能を実装しました。`holidays` gemを使用して祝日データを動的に取得し、カレンダーのイベント一覧に終日イベントとして表示します。

---

## 🎯 実装内容

### 1. Gem の追加
**ファイル:** `Gemfile`

```ruby
# Japanese holidays data
gem "holidays"
```

- バージョン: 11.1.0
- 日本の祝日データを動的に取得

---

### 2. CalendarController の拡張

#### 2-1. HolidayEvent クラスの定義
**ファイル:** `app/controllers/calendar_controller.rb` (1-64行目)

祝日イベントを表すクラスを定義し、Event モデルと同じインターフェースを提供します。

**主要な属性:**
- `id`: ユニークID（"holiday_20260720_海の日" 形式）
- `title`: 祝日名（例: "海の日"）
- `start_time`, `end_time`: 祝日の日付（Time型）
- `all_day`: true（終日フラグ）
- `is_holiday`: true（祝日フラグ）
- `event_type`: "holiday"
- `color`: "#DC2626"（赤色）

**主要なメソッド:**
- `all_day?` → true
- `recurring?` → false
- `display_category_name` → 祝日名
- `display_color` → 赤色

---

#### 2-2. add_holiday_events メソッド
**ファイル:** `app/controllers/calendar_controller.rb` (1154-1190行目)

`Holidays.between` メソッドを使って日本の祝日（`:jp` リージョン）を取得し、HolidayEvent インスタンスとして @events に追加します。

**処理フロー:**
1. 指定期間の日本の祝日を取得（observed holidays を含む）
2. 各祝日を HolidayEvent インスタンスに変換
3. @events 配列に追加
4. ログ出力（取得した祝日数、各祝日の詳細）

**エラーハンドリング:**
- LoadError: holidays gem の読み込み失敗
- StandardError: 一般的なエラー

---

#### 2-3. カレンダー表示メソッドの修正

**show_month メソッド** (805-825行目):
```ruby
# holidays gem から祝日を取得してイベントリストに追加
if @calendar_settings[:show_holidays]
  add_holiday_events(@start_date, @end_date)
end
```

**show_week メソッド** (845-855行目):
```ruby
# holidays gem から祝日を取得してイベントリストに追加
if @calendar_settings[:show_holidays]
  add_holiday_events(@start_date, @end_date)
end
```

**show_day メソッド** (865-875行目):
```ruby
# holidays gem から祝日を取得してイベントリストに追加
if @calendar_settings[:show_holidays]
  add_holiday_events(@start_date, @end_date)
end
```

---

#### 2-4. events API の修正
**ファイル:** `app/controllers/calendar_controller.rb` (574-640行目)

JSON API エンドポイントで祝日イベントも返すように修正しました。

**HolidayEvent の場合の追加プロパティ:**
- `is_holiday`: true
- `classNames`: ['holiday-event']

**レスポンス例:**
```json
{
  "id": "holiday_20260720_海の日",
  "title": "海の日",
  "start": "2026-07-20T00:00:00+09:00",
  "end": "2026-07-20T23:59:00+09:00",
  "allDay": true,
  "backgroundColor": "#DC2626",
  "borderColor": "#DC2626",
  "eventType": "holiday",
  "is_holiday": true,
  "classNames": ["holiday-event"]
}
```

---

### 3. ビューの修正

#### 3-1. 月表示 (index.html.haml)
**ファイル:** `app/views/calendar/index.html.haml` (113-123行目)

```haml
- day_data[:events].each do |event|
  - is_holiday = event.respond_to?(:is_holiday) && event.is_holiday
  - if is_holiday
    .calendar-event.holiday-event{ title: "#{event.title}（祝日）" }
      = event.title.truncate(15)
  - else
    .calendar-event{ ... }
      = event.title.truncate(15)
```

**変更点:**
- 祝日イベントの場合、`.holiday-event` クラスを追加
- クリックイベントを無効化（編集不可）
- ツールチップに「（祝日）」を表示

---

#### 3-2. 週表示 (index.html.haml)
**ファイル:** `app/views/calendar/index.html.haml` (151-165行目)

```haml
- allday_ev.each do |event|
  - is_holiday = event.respond_to?(:is_holiday) && event.is_holiday
  - if is_holiday
    .week-allday-event.holiday-event{ title: "#{event.title}（祝日）" }
      = event.title.truncate(16)
  - else
    .week-allday-event{ ... }
      = event.title.truncate(16)
```

**変更点:**
- 終日イベントエリアで祝日を表示
- `.holiday-event` クラスで赤色表示
- クリックイベントを無効化

---

### 4. CSS スタイル
**ファイル:** `app/assets/stylesheets/application.css` (165-208行目)

#### 4-1. 祝日イベントの基本スタイル
```css
.holiday-event {
  background-color: #fee2e2 !important; /* 薄い赤色 */
  border-color: #dc2626 !important;
  color: #991b1b !important;
  font-weight: 600;
}

.holiday-event:hover {
  background-color: #fecaca !important;
  cursor: default !important; /* 編集不可を示す */
}
```

#### 4-2. 週表示の祝日イベント
```css
.week-allday-event.holiday-event {
  background-color: #fee2e2 !important;
  border-left: 3px solid #dc2626 !important;
  color: #991b1b !important;
}
```

#### 4-3. ダークモード対応
```css
@media (prefers-color-scheme: dark) {
  .holiday-event {
    background-color: #7f1d1d !important;
    color: #fecaca !important;
  }
}
```

---

## 🚀 使い方

### 自動表示（推奨）

カレンダー設定で「祝日を表示」が有効な場合、自動的に祝日が表示されます。

**設定パス:** カレンダー > 設定 > 祝日を表示

### 表示される祝日

`holidays` gem の `:jp` リージョンに基づいて、以下の祝日が自動的に表示されます：

- 元日（1月1日）
- 成人の日（1月第2月曜日）
- 建国記念の日（2月11日）
- 天皇誕生日（2月23日）
- 春分の日（3月20日前後）
- 昭和の日（4月29日）
- 憲法記念日（5月3日）
- みどりの日（5月4日）
- こどもの日（5月5日）
- 海の日（7月第3月曜日）
- 山の日（8月11日）
- 敬老の日（9月第3月曜日）
- 秋分の日（9月23日前後）
- スポーツの日（10月第2月曜日）
- 文化の日（11月3日）
- 勤労感謝の日（11月23日）

**振替休日や特別な祝日も自動的に含まれます。**

---

## 🎨 デザイン仕様

### カラーパレット

| 要素 | ライトモード | ダークモード |
|-----|------------|------------|
| 背景色 | #fee2e2（薄い赤） | #7f1d1d（濃い赤） |
| ボーダー色 | #dc2626（赤） | #dc2626（赤） |
| テキスト色 | #991b1b（暗い赤） | #fecaca（薄い赤） |
| ホバー時 | #fecaca | #991b1b |

### 表示形式

- **月表示:** 日付セル内に祝日名を赤色で表示
- **週表示:** 終日イベントエリアに赤色の祝日イベントを表示
- **日表示:** 終日イベントとして表示

---

## 🔧 トラブルシューティング

### 祝日が表示されない

**確認項目:**
1. カレンダー設定で「祝日を表示」が有効か
   ```
   カレンダー > 設定 > 祝日を表示 ✓
   ```

2. holidays gem が正しくインストールされているか
   ```bash
   bundle list | grep holidays
   # => * holidays (11.1.0)
   ```

3. ログで祝日取得が成功しているか
   ```bash
   tail -f log/development.log | grep "🎌"
   # => 🎌 Found 16 Japanese holidays between 2026-01-01 and 2026-12-31
   ```

### LoadError が発生する

**原因:** holidays gem が読み込めていない

**解決方法:**
```bash
bundle install
bin/rails server -d
```

### 祝日の数が少ない

**原因:** 表示期間が短い

**確認:**
- 月表示: カレンダーの前後の週も含む（約5-6週間分）
- 週表示: 選択した週のみ（7日間）
- 日表示: 選択した日のみ

---

## 📊 実装ファイル一覧

| ファイル | 説明 | 変更内容 |
|---------|------|---------|
| `Gemfile` | gem 依存関係 | holidays gem 追加 |
| `app/controllers/calendar_controller.rb` | カレンダーコントローラー | HolidayEventクラス、add_holiday_eventsメソッド追加、各メソッド修正 |
| `app/views/calendar/index.html.haml` | カレンダービュー | 祝日イベントの条件分岐と表示ロジック追加 |
| `app/assets/stylesheets/application.css` | CSS スタイル | 祝日イベント用スタイル追加 |

---

## ✨ 機能の特徴

- ✅ **自動取得**: holidays gem で日本の祝日を動的に取得
- ✅ **メンテナンスフリー**: 手動で祝日データを更新する必要なし
- ✅ **設定連動**: カレンダー設定の「祝日を表示」で ON/OFF 切り替え
- ✅ **編集不可**: 祝日イベントはクリックできず、誤編集を防止
- ✅ **視覚的識別**: 赤色で表示され、一目で祝日と分かる
- ✅ **ダークモード対応**: ライト/ダークモード両方で適切に表示
- ✅ **API 対応**: JSON API でも祝日データを返す
- ✅ **振替休日対応**: 振替休日も自動的に含まれる

---

## 🔄 既存機能との互換性

### Holiday モデルとの関係

既存の `Holiday` モデル（DB ベース）は残されており、引き続き使用可能です：

- **従来:** DB の holidays テーブルから祝日を取得
- **新機能:** holidays gem から動的に取得（HolidayEvent として @events に追加）

**両方が共存:**
- `@holidays`: DB ベースの祝日データ（既存機能）
- `@events`: イベントリスト（通常イベント + holidays gem からの祝日）

**将来的な移行:**
- DB ベースの Holiday モデルを削除することも可能
- 現時点では互換性維持のため両方を保持

---

## 🎉 完了

これでカレンダーに日本の祝日が自動的に表示されるようになりました！

**更新日:** 2026-07-21  
**バージョン:** 1.0  
**依存gem:** holidays 11.1.0
