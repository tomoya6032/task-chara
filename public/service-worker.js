// PWA最適化版 Service Worker
// - App Shellキャッシュで高速起動
// - Network Firstでログイン状態を正確に反映
// - Herokuスリープ対策（タイムアウト処理）
// - POST/PATCH/DELETE は Service Worker をバイパス
// - Turbo Stream リクエストもバイパス
// - リダイレクトを正常なレスポンスとして扱う

const CACHE_NAME = 'task-character-v6.0-turbo-fixed';
const APP_SHELL_CACHE = 'task-character-app-shell-v6.0';
const RUNTIME_CACHE = 'task-character-runtime-v6.0';
const TIMEOUT_DURATION = 8000; // 8秒でタイムアウト（Heroku起動待ち）

// App Shell: アプリの骨組（即座にキャッシュから表示）
const APP_SHELL_URLS = [
  '/',
  '/icon-192.png',
  '/icon-512.png',
  '/favicon.ico',
  '/offline.html'
];

// 静的アセット: 画像、フォント等
const STATIC_ASSETS_REGEX = /\.(png|jpg|jpeg|gif|svg|ico|webp|woff|woff2|ttf|eot)$/;

// API/データリクエスト: タイムアウト処理が必要
const API_REGEX = /\/(api|tasks|activities|calendar|dashboards)/;

// ===============================================
// インストール: App Shellをプリキャッシュ
// ===============================================
self.addEventListener('install', (event) => {
  console.log('[Service Worker] Installing v6 - Turbo & POST/PATCH/DELETE Fixed');
  event.waitUntil(
    caches.open(APP_SHELL_CACHE)
      .then((cache) => {
        console.log('[Service Worker] Caching App Shell');
        return cache.addAll(APP_SHELL_URLS.map(url => new Request(url, { cache: 'reload' })));
      })
      .then(() => {
        console.log('[Service Worker] App Shell cached successfully');
        return self.skipWaiting();
      })
      .catch((error) => {
        console.error('[Service Worker] App Shell caching failed:', error);
      })
  );
});

// ===============================================
// アクティベーション: 古いキャッシュ削除
// ===============================================
self.addEventListener('activate', (event) => {
  console.log('[Service Worker] Activating v6 - Turbo Fixed');
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME && 
              cacheName !== APP_SHELL_CACHE && 
              cacheName !== RUNTIME_CACHE) {
            console.log('[Service Worker] Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => {
      console.log('[Service Worker] Claiming clients');
      return self.clients.claim();
    })
  );
});

// ===============================================
// Fetch: リクエスト処理の振り分け
// ===============================================
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);
  
  // 同一オリジンでない場合はスルー
  if (url.origin !== location.origin) {
    return;
  }

  // 🔥 GET以外のメソッド（POST/PATCH/DELETE等）は Service Worker を通さない
  // フォーム送信やAPIの変更処理はキャッシュせず、常にサーバーへ直接送信
  if (request.method !== 'GET') {
    console.log('[Service Worker] Non-GET request - bypassing SW:', request.method, request.url);
    return; // Service Worker をスキップしてネットワークへ
  }

  // 🔥 Turbo Stream リクエストは常にネットワークへ（キャッシュしない）
  // Turbo による動的更新は常に最新の内容が必要
  const acceptHeader = request.headers.get('Accept') || '';
  if (acceptHeader.includes('text/vnd.turbo-stream.html')) {
    console.log('[Service Worker] Turbo Stream request - bypassing SW:', request.url);
    return; // Service Worker をスキップしてネットワークへ
  }

  // ログイン/認証系は常にネットワーク優先（キャッシュしない）
  if (url.pathname.includes('/users/sign_in') || 
      url.pathname.includes('/users/sign_out') ||
      url.pathname.includes('/users/sign_up')) {
    event.respondWith(fetchWithTimeout(request, TIMEOUT_DURATION));
    return;
  }

  // カレンダーイベント詳細JSON: Network Only（キャッシュしない）
  // 削除された予定の古いキャッシュが表示されるのを防ぐ
  if (url.pathname.match(/^\/calendar\/\d+/) && request.headers.get('Accept')?.includes('application/json')) {
    event.respondWith(fetchWithTimeout(request, TIMEOUT_DURATION));
    return;
  }

  // HTMLナビゲーション: Stale-While-Revalidate + タイムアウト処理
  if (request.mode === 'navigate' || 
      request.destination === 'document' ||
      request.headers.get('Accept')?.includes('text/html')) {
    event.respondWith(handleNavigationRequest(request));
    return;
  }
  
  // 静的アセット: Cache First（永続的にキャッシュ）
  if (url.pathname.match(STATIC_ASSETS_REGEX)) {
    event.respondWith(handleStaticAsset(request));
    return;
  }
  
  // API/データリクエスト: Network First + タイムアウト処理
  if (url.pathname.match(API_REGEX)) {
    event.respondWith(handleApiRequest(request));
    return;
  }
  
  // その他: Network First
  event.respondWith(fetchWithTimeout(request, TIMEOUT_DURATION));
});

// ===============================================
// ナビゲーションリクエスト処理 (Network First)
// ログイン状態が反映されるよう、常にネットワークを優先
// ===============================================
async function handleNavigationRequest(request) {
  try {
    console.log('[Service Worker] Navigation (Network First):', request.url);
    
    // ⚡ まずネットワークから取得（ログイン状態を正しく反映）
    try {
      const networkResponse = await fetchWithTimeout(request, TIMEOUT_DURATION);
      
      // 🔥 リダイレクト（302/303等）も成功として扱う
      if (networkResponse && (networkResponse.ok || networkResponse.redirected || 
          (networkResponse.status >= 300 && networkResponse.status < 400))) {
        // 200 OK, リダイレクト、その他の成功レスポンスをキャッシュ
        if (networkResponse.status === 200) {
          caches.open(RUNTIME_CACHE).then(cache => {
            cache.put(request, networkResponse.clone());
          });
        }
        console.log('[Service Worker] Serving from network (fresh):', networkResponse.status, request.url);
        return networkResponse;
      }
    } catch (networkError) {
      // 🔥 本当にオフライン（ネットワークなし）の場合のみキャッシュへフォールバック
      if (!navigator.onLine) {
        console.warn('[Service Worker] Offline detected, trying cache:', networkError);
      } else {
        // オンラインなのにエラー = サーバーエラーやタイムアウト
        // この場合はエラーをそのまま返す（オフライン画面を表示しない）
        console.error('[Service Worker] Network error (but online):', networkError);
        throw networkError;
      }
    }
    
    // 本当にオフラインの場合のみキャッシュから返す
    if (!navigator.onLine) {
      const cachedResponse = await caches.match(request);
      if (cachedResponse) {
        console.log('[Service Worker] Serving from cache (offline fallback):', request.url);
        return cachedResponse;
      }
      
      // キャッシュもない場合はオフライン画面
      return caches.match('/offline.html') || new Response(
        '<h1>オフラインです</h1><p>ネットワーク接続を確認してください。</p>',
        { headers: { 'Content-Type': 'text/html; charset=utf-8' } }
      );
    }
    
    // オンラインだがエラー発生 = サーバーの問題なのでエラーを再スロー
    throw new Error('Network request failed but device is online');
    
  } catch (error) {
    console.error('[Service Worker] Navigation error:', error);
    // オフラインの場合のみオフライン画面を表示
    if (!navigator.onLine) {
      return caches.match('/offline.html');
    }
    // オンラインの場合はエラーをそのまま返す（ブラウザのデフォルトエラー表示）
    throw error;
  }
}

// ===============================================
// 静的アセット処理: Cache First
// ===============================================
async function handleStaticAsset(request) {
  try {
    const cachedResponse = await caches.match(request);
    if (cachedResponse) {
      console.log('[Service Worker] Serving static asset from cache:', request.url);
      return cachedResponse;
    }
    
    const networkResponse = await fetch(request);
    if (networkResponse && networkResponse.status === 200) {
      const cache = await caches.open(APP_SHELL_CACHE);
      cache.put(request, networkResponse.clone());
    }
    return networkResponse;
    
  } catch (error) {
    console.error('[Service Worker] Static asset error:', error);
    return new Response('Not found', { status: 404 });
  }
}

// ===============================================
// API リクエスト処理: Network First + タイムアウト
// ===============================================
async function handleApiRequest(request) {
  try {
    console.log('[Service Worker] API request:', request.url);
    const networkResponse = await fetchWithTimeout(request, TIMEOUT_DURATION);
    
    // 成功したらキャッシュに保存
    if (networkResponse && networkResponse.status === 200) {
      const cache = await caches.open(RUNTIME_CACHE);
      cache.put(request, networkResponse.clone());
    }
    
    return networkResponse;
    
  } catch (error) {
    console.warn('[Service Worker] API request failed, trying cache:', error);
    
    // ネットワーク失敗時はキャッシュから返す
    const cachedResponse = await caches.match(request);
    if (cachedResponse) {
      return cachedResponse;
    }
    
    // キャッシュもない場合はエラーレスポンス
    return new Response(
      JSON.stringify({ error: 'Network error', message: 'サーバーに接続できません' }),
      { status: 503, headers: { 'Content-Type': 'application/json' } }
    );
  }
}

// ===============================================
// タイムアウト付きFetch（Herokuスリープ対策）
// ===============================================
function fetchWithTimeout(request, timeout = TIMEOUT_DURATION) {
  return Promise.race([
    fetch(request).then(response => {
      // 🔥 リダイレクト（302/303等）も正常なレスポンスとして扱う
      if (response.redirected || (response.status >= 300 && response.status < 400)) {
        console.log('[Service Worker] Redirect detected:', response.status, response.url);
      }
      return response;
    }),
    new Promise((_, reject) => 
      setTimeout(() => reject(new Error('Request timeout')), timeout)
    )
  ]).catch(error => {
    console.error('[Service Worker] Fetch timeout or error:', error);
    throw error;
  });
}
