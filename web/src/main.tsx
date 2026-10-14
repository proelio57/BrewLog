import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { repository, sound } from './app'
import { Shell } from './Shell'
import './styles.css'

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
