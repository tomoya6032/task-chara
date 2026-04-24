module ApplicationHelper
  def nav_link_class(path, active = false)
    base_classes = "group flex gap-x-3 rounded-md p-2 text-sm leading-6 font-semibold transition-colors"

    if active || current_page?(path)
      "#{base_classes} bg-slate-50 text-slate-700 dark:bg-slate-700 dark:text-slate-200"
    else
      "#{base_classes} text-slate-400 hover:text-slate-700 hover:bg-slate-50 dark:text-slate-400 dark:hover:text-slate-200 dark:hover:bg-slate-700"
    end
  end
end
