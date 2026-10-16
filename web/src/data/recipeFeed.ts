import { PRESET_RECIPES } from '../domain/library'
import type { Recipe } from '../domain/recipe'
import { decodeRecipes } from '../import/recipeFile'
import { Store } from './store'

// Port of RecipeFeed.swift / RecipeFeed.kt: downloads the shared recipes.json every few hours, so new and changed
// recipes show up without an app update. The last good download is cached on the device.

export const FEED_URL: string =
  (import.meta.env?.VITE_RECIPE_FEED_URL as string | undefined) ?? 'https://raw.githubusercontent.com/proelio57/BrewLog/sidestore/recipes.json'
export const CHECK_INTERVAL_MS = 6 * 3600 * 1000
export const MAX_DOWNLOAD_SIZE = 1024 * 1024
const CACHE_KEY = 'brewlog.recipeFeed'

/** Bundled recipes first (in their order, replaced by newer online versions), then new online recipes. */
export function mergeFeed(bundled: Recipe[], remote: Recipe[]): Recipe[] {
  const byId = new Map<string, Recipe>()
  for (const recipe of remote) if (recipe.id) byId.set(recipe.id, { ...recipe, isCustom: null })
  const bundledIds = new Set(bundled.map((r) => r.id))
  const seen = new Set<string>()
  const added: Recipe[] = []
  for (const recipe of remote) {
    const merged = byId.get(recipe.id)
    if (merged && !bundledIds.has(recipe.id) && !seen.has(recipe.id)) {
      seen.add(recipe.id)
      added.push(merged)
    }
  }
  return [...bundled.map((r) => byId.get(r.id) ?? r), ...added]
}

export interface FeedStatus { lastSync: number | null; error: string | null; syncing: boolean }

interface Cache { recipes: unknown; lastSync: number }

function readCache(): Cache | null {
  try {
    const parsed = JSON.parse(localStorage.getItem(CACHE_KEY) ?? 'null') as Cache | null
    return parsed && typeof parsed.lastSync === 'number' ? parsed : null
  } catch {
    return null
  }
}

export class RecipeFeed {
  readonly presets: Store<Recipe[]>
  readonly status: Store<FeedStatus>

  constructor(private readonly enabled: () => boolean, private readonly url = FEED_URL, private readonly fetcher: typeof fetch = (...a) => fetch(...a)) {
    const cache = typeof localStorage !== 'undefined' ? readCache() : null
    let cached: Recipe[] = []
    try {
      if (cache) cached = decodeRecipes(cache.recipes)
    } catch {
      cached = []
    }
    this.presets = new Store(mergeFeed(PRESET_RECIPES, cached))
    this.status = new Store<FeedStatus>({ lastSync: cache?.lastSync ?? null, error: null, syncing: false })
  }

  /** Downloads the list if the last check is older than 6 hours (or `force`). */
  async syncIfNeeded(force = false): Promise<void> {
    const status = this.status.get()
    if (!this.enabled() || !this.url.startsWith('https://') || status.syncing) return
    if (!force && status.lastSync != null && Date.now() - status.lastSync < CHECK_INTERVAL_MS) return
    this.status.set({ ...status, syncing: true })
    try {
      const response = await this.fetcher(this.url, { cache: 'no-store', headers: { Accept: 'application/json' } })
      if (!response.ok) throw new Error(`The recipe list isn't available (HTTP ${response.status}).`)
      const text = await response.text()
      if (text.length > MAX_DOWNLOAD_SIZE) throw new Error('The recipe list is too large.')
      const raw = JSON.parse(text) as unknown
      const remote = decodeRecipes(raw)
      const lastSync = Date.now()
      try {
        localStorage.setItem(CACHE_KEY, JSON.stringify({ recipes: raw, lastSync } satisfies Cache))
      } catch {
        // Storage full or blocked: the list still applies until the next reload.
      }
      this.presets.set(mergeFeed(PRESET_RECIPES, remote))
      this.status.set({ lastSync, error: null, syncing: false })
    } catch (error) {
      this.status.set({ ...this.status.get(), error: error instanceof Error ? error.message : 'Sync failed', syncing: false })
    }
  }
}
