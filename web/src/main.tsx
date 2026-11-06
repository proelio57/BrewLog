import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { espressoSetup, repository, scale, settings, setup, sound } from './app'
import { Shell } from './Shell'
import './styles.css'

// Expose singletons for automated screenshot capturing and E2E tests
if (typeof window !== 'undefined') {
  const w = window as unknown as Record<string, unknown>
  w.repository = repository
  w.scale = scale
  w.settings = settings
  w.setup = setup
  w.espressoSetup = espressoSetup
}

// Browsers only allow audio after a user gesture: unlock it on the first tap.
window.addEventListener('pointerdown', () => sound.unlock(), { once: true })
// Write pending changes before the page is hidden, closed or reloaded.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') repository.flush()
})
window.addEventListener('pagehide', () => repository.flush())

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(() => undefined)
  })
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Shell />
  </StrictMode>,
)
