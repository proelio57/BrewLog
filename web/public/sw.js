// Offline support. Navigations are network-first (so updates arrive), assets cache-first (hashed file names).
// The bundles referenced by index.html are cached at install, so the app works offline right after the first visit.
const CACHE = 'brewlog-v1'
const SHELL = ['./', './index.html', './manifest.webmanifest', './icon.svg', './icon-192.png', './icon-512.png', './apple-touch-icon.png']

/** Absolute URLs of the hashed bundles an index.html references. */
const assetsIn = (html) =>
  [...html.matchAll(/(?:src|href)="\.\/(assets\/[^"]+)"/g)].map((match) => new URL(match[1], self.registration.scope).href)

async function precache() {
  const cache = await caches.open(CACHE)
  await cache.addAll(SHELL)
  const index = await cache.match('./index.html')
  if (index) await cache.addAll(assetsIn(await index.text()))
}

/** Stores a fresh index.html and drops bundles of older versions (they're never requested again). */
async function updateIndex(response) {
  const cache = await caches.open(CACHE)
  await cache.put('./index.html', response.clone())
  const keep = new Set(assetsIn(await response.text()))
  for (const request of await cache.keys()) {
    if (new URL(request.url).pathname.includes('/assets/') && !keep.has(request.url)) await cache.delete(request)
  }
}

self.addEventListener('install', (event) => {
  event.waitUntil(precache())
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  )
})

self.addEventListener('fetch', (event) => {
  const request = event.request
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (response.ok) event.waitUntil(updateIndex(response.clone()))
          return response
        })
        .catch(async () => (await caches.match('./index.html')) ?? Response.error()),
    )
    return
  }

  event.respondWith(
    caches.match(request).then((cached) =>
      cached ||
      fetch(request).then((response) => {
        if (response.ok) {
          const copy = response.clone()
          event.waitUntil(caches.open(CACHE).then((cache) => cache.put(request, copy)))
        }
        return response
      }),
    ),
  )
})
