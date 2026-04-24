// app/assets/javascripts/activity_task_extraction.js
document.addEventListener('DOMContentLoaded', function() {
  setupTaskExtractionHandlers();
});

document.addEventListener('turbo:load', function() {
  setupTaskExtractionHandlers();
});

function setupTaskExtractionHandlers() {
  // タスク抽出ボタンにイベントリスナーを設定
  const extractButtons = document.querySelectorAll('form[action*="extract_tasks"] button[type="submit"]');
  
  extractButtons.forEach(button => {
    const form = button.closest('form');
    if (form && !form.hasEventListener) {
      form.hasEventListener = true;
      
      form.addEventListener('submit', function(e) {
        e.preventDefault();
        handleTaskExtraction(this, button);
      });
    }
  });
}

async function handleTaskExtraction(form, button) {
  const actionUrl = form.action;
  const originalButtonText = button.innerHTML;
  const originalButtonState = button.disabled;

  try {
    // ボタンの状態を更新
    button.innerHTML = '🤖 AIが解析中...';
    button.disabled = true;

    // CSRFトークンを取得
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');

    // Fetch APIでリクエストを送信
    const response = await fetch(actionUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-CSRF-Token': csrfToken,
        'X-Requested-With': 'XMLHttpRequest'
      }
    });

    const result = await response.json();

    if (response.ok && result.success) {
      // 成功時の処理
      showTaskExtractionSuccess(result);
    } else {
      // エラー時の処理
      showTaskExtractionError(result.message || 'タスクの抽出に失敗しました');
    }

  } catch (error) {
    console.error('Task extraction error:', error);
    showTaskExtractionError('ネットワークエラーが発生しました: ' + error.message);
  } finally {
    // ボタンの状態を復元
    button.innerHTML = originalButtonText;
    button.disabled = originalButtonState;
  }
}

function showTaskExtractionSuccess(result) {
  const message = `✅ ${result.message}\n\n抽出されたタスク数: ${result.tasks_count}件`;
  
  // 成功モーダルを表示
  if (result.created_tasks && result.created_tasks.length > 0) {
    const taskList = result.created_tasks.map(task => 
      `• ${task.title} (${getCategoryDisplayName(task.category)})`
    ).join('\n');
    
    alert(`${message}\n\n作成されたタスク:\n${taskList}\n\nダッシュボードまたはタスク一覧で確認できます。`);
  } else {
    alert(message + '\n\nダッシュボードまたはタスク一覧で確認できます。');
  }

  // ページのリロード（オプション）
  if (confirm('タスク一覧を確認しますか？')) {
    window.location.href = '/dashboard';
  }
}

function showTaskExtractionError(message) {
  alert(`❌ エラー: ${message}\n\n別の内容の日報で再度お試しください。`);
}

function getCategoryDisplayName(category) {
  switch (category) {
    case 'welfare':
      return '訪問福祉 🏠';
    case 'web':
      return 'Web制作 💻';
    case 'admin':
      return '事務作業 📋';
    default:
      return category;
  }
}