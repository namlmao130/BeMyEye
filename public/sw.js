/**
 * Service Worker cho Be My Eyes VN PWA
 * Hỗ trợ lưu trữ offline và khởi động tức thì như ứng dụng Native
 */

const CACHE_NAME = 'bemyeye-v1';
const ASSETS_TO_CACHE = [
  '/',
  '/index.html',
  '/styles.css',
  '/manifest.json',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/js/app.js',
  '/js/audio_haptics.js',
  '/js/spatial_analyzer.js',
  '/js/ground_analyzer.js',
  '/js/depth_analyzer.js',
  '/js/detector.js',
  '/js/alert_engine.js',
  '/js/metrics_logger.js',
  '/js/battery_optimizer.js',
  '/js/navigation_engine.js',
  '/js/camera.js'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(ASSETS_TO_CACHE);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }
        })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      if (cachedResponse) {
        return cachedResponse;
      }
      return fetch(event.request);
    })
  );
});
