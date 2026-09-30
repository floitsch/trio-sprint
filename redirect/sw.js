// Copyright (C) 2026 Toit contributors.
// Replace the old offline worker so cached installs also reach the new host.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('trio-')) await caches.delete(key);
    }
    await self.clients.claim();
    // Existing games keep running; the next navigation follows the redirect.
  })());
});
self.addEventListener('fetch', event => {
  if (event.request.mode === 'navigate') {
    // Let the redirect page read location.hash, which fetch requests omit.
    event.respondWith(fetch(new URL('index.html', self.registration.scope), { cache: 'no-store' }));
  }
});
