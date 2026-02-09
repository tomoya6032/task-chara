# HAMLでのform.select構文テスト
# 現在のコード（エラーが発生する可能性）
= form.select :category, 
  options_for_select([
    ['訪問福祉 🏠', 'welfare'],
    ['Web制作 💻', 'web'],
    ['事務作業 📋', 'admin']
  ], @task.category), 
  {}, 
  { class: "w-full rounded-lg..." }

# 修正版1: 改行を少なくする
= form.select :category, options_for_select([['訪問福祉 🏠', 'welfare'], ['Web制作 💻', 'web'], ['事務作業 📋', 'admin']], @task.category), {}, { class: "w-full rounded-lg..." }

# 修正版2: HTMLオプションを別行に
= form.select :category, options_for_select([['訪問福祉 🏠', 'welfare'], ['Web制作 💻', 'web'], ['事務作業 📋', 'admin']], @task.category), {},
  class: "w-full rounded-lg..."

# 修正版3: インデント調整版
= form.select :category,
  options_for_select([
    ['訪問福祉 🏠', 'welfare'],
    ['Web制作 💻', 'web'],
    ['事務作業 📋', 'admin']
  ], @task.category),
  {},
  class: "w-full rounded-lg border-slate-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white shadow-sm focus:border-blue-500 focus:ring-blue-500"