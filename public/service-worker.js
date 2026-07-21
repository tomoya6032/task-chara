const CACHE_NAME = 'task-character-v3';  // 無限ループ修正後のバージョン
const urlsToCache = [
  '/icon-192.png',
  '/icon-512.png',
  '/favicon.ico'
];

// インストール時のキャッシュ処理
self.addEventListener('install', (event) => {
  console.log('[Service Worker] Installing...');
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        console.log('[Service Worker] Caching app shell');
        return cache.addAll(urlsToCache);
      })
      .then(() => self.skipWaiting())
  );
});

// アクティベーション時の古いキャッシュ削除
self.addEventListener('activate', (event) => {
  console.log('[Service Worker] Activating...');
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME) {
            console.log('[Service Worker] Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch時の処理
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  
  // 同一オリジンでない場合はスルー（外部API等）
  if (url.origin !== location.origin) {
    return;
  }
  
  // HTMLナビゲーション（ページ遷移）は常にネットワークを使用
  // これによりTurboの動作を妨げない
  if (event.request.mode === 'navigate' || 
      event.request.destination === 'document' ||
      event.request.headers.get('Accept')?.includes('text/html')) {
    console.log('[Service Worker] Navigation request - using network only:', url.pathname);
    event.respondWith(
      fetch(event.request, { cache: 'no-store' }).catch(() => {
        // ネットワークエラー時のみキャッシュから返す
        return caches.match(event.request);
      })
    );
    return;
  }
  
  // 静的アセット（画像、アイコン等）のみキャッシュを使用
  if (url.pathname.match(/\.(png|jpg|jpeg|gif|svg|ico|webp)$/)) {
    event.respondWith(
      caches.match(event.request).then((response) => {
        if (response) {
          console.log('[Service Worker] Serving from cache:', url.pathname);
          return response;
        }
        
        return fetch(event.request).then((response) => {
          // 成功したレスポンスをキャッシュに保存
          if (response && response.status === 200) {
            const responseToCache = response.clone();
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(event.request, responseToCache);
            });
          }
          return response;
        });
      })
    );
    return;
  }
  
  // その他のリクエストはネットワークを優先（キャッシュなし）
  event.respondWith(fetch(event.request));
});
