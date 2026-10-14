import { useEffect, useState } from 'react'
import { SoundPlayer, WakeLock } from './audio/sound'
import type { BrewCue, BrewSession } from './brewing/brewSession'
import { Repository } from './data/repository'
import { SettingsStore } from './data/settings'
import { BrewSetup } from './data/setup'
import { PRESET_RECIPES } from './domain/library'
import type { Equipment } from './domain/models'
import type { Recipe } from './domain/recipe'
import { ScaleManager } from './scale/scaleManager'

/** Everything the brew needs, frozen when "Start brew" is pressed. */
export interface BrewConfig {
  recipe: Recipe
  dose: number
  waterTemp: number
  beanId: string | null
  brewer: Equipment | null
  grinder: Equipment | null
  filter: Equipment | null
  grindValue: number | null
  grindText: string
}

// App-wide singletons (simple manual wiring).
export const settings = new SettingsStore()
export const repository = new Repository()
export const scale = new ScaleManager(settings.get().demoScale, (enabled) => settings.change((s) => ({ ...s, demoScale: enabled })))
export const sound = new SoundPlayer(() => settings.get())
export const wakeLock = new WakeLock()
export const allRecipes = (): Recipe[] => [...repository.data.get().customRecipes, ...PRESET_RECIPES]
export const setup = new BrewSetup(allRecipes)

/** The live brew survives re-renders and navigation because it lives here. */
export const live: { brew: { config: BrewConfig; session: BrewSession } | null } = { brew: null }

export const cue = (c: BrewCue): void => sound.cue(c)

// MARK: - Hash router

export interface Route {
  path: string
  segments: string[]
  query: URLSearchParams
}

function parseHash(): Route {
  const hash = window.location.hash.replace(/^#/, '') || '/brew'
  const [path, search = ''] = hash.split('?')
  return { path, segments: path.split('/').filter(Boolean), query: new URLSearchParams(search) }
}

export function useRoute(): Route {
  const [route, setRoute] = useState(parseHash)
  useEffect(() => {
    const onChange = () => setRoute(parseHash())
    window.addEventListener('hashchange', onChange)
    return () => window.removeEventListener('hashchange', onChange)
  }, [])
  return route
}

/** Per history entry: how many in-app screens lie below it, and where the screen was scrolled. */
interface HistoryState { depth: number; scrollY: number }
const historyState = (): HistoryState => {
  const state = window.history.state as Partial<HistoryState> | null
  return { depth: typeof state?.depth === 'number' ? state.depth : 0, scrollY: typeof state?.scrollY === 'number' ? state.scrollY : 0 }
}
if (typeof window !== 'undefined' && 'scrollRestoration' in window.history) window.history.scrollRestoration = 'manual'

export function navigate(path: string, replace = false): void {
  const { depth } = historyState()
  if (replace) {
    window.history.replaceState({ depth, scrollY: 0 } satisfies HistoryState, '', `#${path}`)
  } else {
    // Remember the scroll position of the screen we leave, so Back returns to the same spot.
    window.history.replaceState({ depth, scrollY: window.scrollY } satisfies HistoryState, '')
    window.history.pushState({ depth: depth + 1, scrollY: 0 } satisfies HistoryState, '', `#${path}`)
  }
  window.dispatchEvent(new HashChangeEvent('hashchange'))
}

/** Back within the app; never leaves it (e.g. after opening a deep link), falls back to a tab instead. */
export function goBack(fallback = '/brew'): void {
  if (historyState().depth > 0) window.history.back()
  else navigate(fallback, true)
}

/** Scroll position to show after a route change: top for new screens, the remembered spot after Back. */
export const restoredScrollY = (): number => historyState().scrollY
