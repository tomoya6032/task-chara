# カレンダー予定重なり問題 修正レポート

## 🔍 問題の特定

### 1. z-index計算ロジックの問題
**修正前:**
```ruby
event_z_index = 1 + col_index
```
- col_index=0（左側）の予定がz-index=1
- col_index=1（右側）の予定がz-index=2
- 長時間の予定が先に配置されるため、col_index=0になることが多い
- **問題**: col_indexによるz-indexでは、長時間の予定が視覚的に他の予定を覆ってしまう

### 2. hover時のz-indexが不十分
**修正前:**
```css
.week-event-block:hover {
  z-index: 4;
}
```
- 最大でz-index=4までしか上がらない
- 複数の予定が重なっている場合、hover時でも隠れてしまう

### 3. タップ領域の最適化不足
**修正前:**
```css
.week-event-block {
  padding: 2px 4px;
  min-height: 14px;
}
```
- モバイルでのタップ領域が小さすぎる（最小でも28px推奨）
- `touch-action`が設定されていない

---

## 🔧 実施した修正

### 1. **z-index計算を期間ベースに変更**
[app/views/calendar/index.html.haml](app/views/calendar/index.html.haml#L252-L255)

**修正後:**
```ruby
- duration_hours = end_hour - start_hour
- event_z_index = (100 - [duration_hours * 5, 80].min).to_i + col_index
```

**計算例:**
- 30分の予定: duration=0.5h → z-index = (100 - 2.5) + 0 = **97**（前面）
- 2時間の予定: duration=2h → z-index = (100 - 10) + 0 = **90**
- 8時間の予定: duration=8h → z-index = (100 - 40) + 0 = **60**
- 24時間の予定: duration=24h → z-index = (100 - 80) + 0 = **20**（背面）

→ **短時間の予定ほど高いz-indexになり、常に前面に表示される**

### 2. **hover/focus/active時のz-indexを大幅に引き上げ**
[app/views/calendar/index.html.haml](app/views/calendar/index.html.haml#L951-L972)

**修正後:**
```css
.week-event-block:hover,
.week-event-block:focus,
.week-event-block:active {
  filter: brightness(0.95);
  box-shadow: 0 4px 12px rgba(0,0,0,0.25);
  z-index: 9999 !important;
}
```

**効果:**
- hover/タップ時に確実に最前面に表示
- `!important`で他のz-indexを上書き
- `focus`と`active`も追加してアクセシビリティ向上

### 3. **タップ領域の最適化（モバイル）**
[app/views/calendar/index.html.haml](app/views/calendar/index.html.haml#L993-L1020)

**修正後:**
```css
@media (max-width: 768px) {
  .week-event-block {
    padding: 4px 3px;
    font-size: 10px;
    min-height: 32px;  /* タップしやすい高さ */
    min-width: 24px;   /* タップしやすい幅 */
  }
  .week-allday-event {
    padding: 4px 6px;
    min-height: 28px;
  }
  .calendar-event {
    padding: 4px 6px;
    min-height: 28px;
    font-size: 10px;
  }
}
```

### 4. **touch-actionの追加**
```css
.week-event-block {
  touch-action: manipulation;
}
```
- タッチデバイスでのスクロールとタップを最適化
- ダブルタップズームを防止

### 5. **終日予定と月表示予定も同様に修正**

**終日予定:**
```css
.week-allday-event {
  position: relative;
  z-index: 10;
  touch-action: manipulation;
}
.week-allday-event:hover {
  z-index: 9999 !important;
}
```

**月表示予定:**
```css
.calendar-event {
  position: relative;
  z-index: 1;
  touch-action: manipulation;
}
.calendar-event:hover {
  z-index: 9999 !important;
}
```

---

## 🧪 検証方法

### ステップ1: 長時間予定と短時間予定の作成
1. カレンダーの週表示を開く
2. 同じ日に以下の予定を作成:
   - **9:00-17:00（8時間）**: 「会議A」
   - **10:00-11:00（1時間）**: 「会議B」
   - **14:00-14:30（30分）**: 「ミーティング」

### ステップ2: 重なり順の確認
**期待される表示:**
- ✅ 「ミーティング」（30分）が最前面に表示される
- ✅ 「会議B」（1時間）が中間に表示される
- ✅ 「会議A」（8時間）が背面に表示される
- ✅ 横にずらして配置され、それぞれタップ可能

### ステップ3: タップ/クリック動作の確認
1. デスクトップ（マウス）:
   - 各予定にマウスホバー → **ホバーした予定が最前面に浮き上がる**
   - クリック → **詳細モーダルが正しく表示される**

2. モバイル/PWA（タッチ）:
   - 各予定を指でタップ → **タップした予定が最前面に浮き上がる**
   - タップ → **詳細モーダルが正しく表示される**
   - 小さな予定（30分）も確実にタップできる

### ステップ4: 複雑な重なりパターンの確認
1. 同じ時間に4つ以上の予定を作成
2. 開発者ツール（F12）→ Elements タブで各予定のz-indexを確認:
   ```
   期待値: 短時間の予定ほど高いz-index（60～100の範囲）
   ```

### ステップ5: 終日予定との重なり確認
1. 終日予定を作成
2. 同じ日に時刻指定の予定を作成
3. 時刻指定の予定がタップできることを確認

---

## 📊 修正の効果

| 項目 | 修正前 | 修正後 |
|------|--------|--------|
| z-index計算 | col_indexベース（1～4） | **期間ベース（20～100）** |
| 短時間予定の表示 | 背面に隠れる | **常に前面** |
| hover時のz-index | 4 | **9999** |
| モバイルタップ領域 | 14px（小さい） | **32px（タップしやすい）** |
| タッチ最適化 | なし | **touch-action: manipulation** |
| 視覚的フィードバック | 弱い | **box-shadow強化** |

---

## 🎯 追加の改善提案（オプション）

### 1. **予定の幅を動的に調整**
現在は重なり数に応じて幅を調整していますが、長時間の予定を意図的に細くすることで、さらに視認性を向上できます：

```ruby
# 長時間の予定は幅を70%に制限
- if duration_hours > 6
  - width_pct *= 0.7
```

### 2. **z-index可視化モード（デバッグ用）**
開発時に各予定のz-indexを表示：

```css
.week-event-block::after {
  content: "z:" attr(data-z-index);
  position: absolute;
  top: 0;
  right: 0;
  font-size: 8px;
  opacity: 0.5;
}
```

### 3. **アニメーションの追加**
hover時にスムーズに浮き上がる効果：

```css
.week-event-block {
  transition: filter 0.15s, box-shadow 0.15s, transform 0.2s, z-index 0s;
}
.week-event-block:hover {
  transform: scale(1.02) translateY(-2px);
}
```

---

## ✅ 完了確認

- [x] z-index計算を期間ベースに変更
- [x] hover/focus/active時のz-indexを9999に引き上げ
- [x] モバイルタップ領域を32pxに拡大
- [x] touch-actionを全予定要素に追加
- [x] 終日予定・月表示予定も同様に修正
- [x] box-shadowを強化して視覚的フィードバック向上

**🎉 カレンダー予定の重なり問題が解消されました！**

上記の検証手順に従って動作確認を行ってください。
