// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "channels"

// タスク期限日時セレクト → hidden フィールドへの同期
window.syncTaskDueDate = function(suffix) {
  const datePart = document.getElementById('task-due-date-part-' + suffix)?.value;
  const hourPart = document.getElementById('task-due-hour-part-' + suffix)?.value;
  const minPart  = document.getElementById('task-due-min-part-' + suffix)?.value;
  const hidden   = document.getElementById('task-due-date-hidden-' + suffix);
  if (!hidden) return;
  if (!datePart) { hidden.value = ''; return; }
  hidden.value = datePart + 'T' + hourPart + ':' + minPart;
};

window.clearTaskDueDate = function(suffix) {
  const dateEl = document.getElementById('task-due-date-part-' + suffix);
  const hidden  = document.getElementById('task-due-date-hidden-' + suffix);
  if (dateEl) dateEl.value = '';
  if (hidden)  hidden.value = '';
};
