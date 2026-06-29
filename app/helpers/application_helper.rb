module ApplicationHelper
  def nav_link_class(path, active = false)
    base_classes = "group flex gap-x-3 rounded-md p-2 text-sm leading-6 font-semibold transition-colors"

    if active || current_page?(path)
      "#{base_classes} bg-slate-50 text-slate-700 dark:bg-slate-700 dark:text-slate-200"
    else
      "#{base_classes} text-slate-400 hover:text-slate-700 hover:bg-slate-50 dark:text-slate-400 dark:hover:text-slate-200 dark:hover:bg-slate-700"
    end
  end

  # 簡易的なMarkdownレンダリング（■見出しと番号付きリストに対応）
  def render_simple_markdown(text)
    return "" if text.blank?

    html = text.dup

    # ■見出しをHTMLに変換（AIが出力する形式）
    html.gsub!(/^■\s*(.+)$/, '<h3 class="text-lg font-semibold text-slate-900 dark:text-white mt-6 mb-3">\1</h3>')

    # 旧形式のMarkdown見出しもサポート（念のため）
    html.gsub!(/^### (.+)$/, '<h3 class="text-lg font-semibold text-slate-900 dark:text-white mt-6 mb-3">\1</h3>')
    html.gsub!(/^## (.+)$/, '<h2 class="text-xl font-bold text-slate-900 dark:text-white mt-8 mb-4">\1</h2>')
    html.gsub!(/^# (.+)$/, '<h1 class="text-2xl font-bold text-slate-900 dark:text-white mt-8 mb-4">\1</h1>')

    # 番号付きリスト（1. 2. 3.）をHTMLに変換
    lines = html.split("\n")
    in_list = false
    result_lines = []

    lines.each do |line|
      if line =~ /^\d+\.\s+(.+)$/
        unless in_list
          result_lines << '<ol class="list-decimal list-inside space-y-1 my-3">'
          in_list = true
        end
        result_lines << "<li>#{$1}</li>"
      else
        if in_list
          result_lines << "</ol>"
          in_list = false
        end
        result_lines << line
      end
    end

    result_lines << "</ol>" if in_list
    html = result_lines.join("\n")

    # 改行を <br> に変換（ただしHTMLタグの直後は除く）
    html.gsub!(/(?<!>)\n(?!<)/, "<br>")

    sanitize(html, tags: %w[h1 h2 h3 p br div ol li strong b u em span mark], attributes: %w[class style])
  end
end
