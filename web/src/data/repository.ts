import { type AppData, type Bean, type Brew, type Equipment, type WeightSample, emptyAppData } from '../domain/models'
import type { Recipe } from '../domain/recipe'
import { LIMITS, parseAppData, parseSamples, validatedRecipe } from '../domain/validation'
import { dbDelete, dbGet, dbKeys, dbSet } from './db'
import { Store } from './store'

const DATA_KEY = 'appdata'
const SAMPLES_PREFIX = 'samples:'
const SAFE_ID = /^[A-Za-z0-9_-]{1,120}$/

/** All app data in IndexedDB. Weight curves are stored per brew so the main record stays small. */
export class Repository {
  readonly data = new Store<AppData>(emptyAppData())
  private readonly samplesCache = new Map<string, WeightSample[]>()
  private saveTimer: ReturnType<typeof setTimeout> | null = null

  async load(): Promise<void> {
    try {
      // Stored data is re-validated before use.
      this.data.set(parseAppData(await dbGet(DATA_KEY)))
    } catch {
      this.data.set(emptyAppData())
    }
  }

  update(transform: (data: AppData) => AppData): void {
    this.data.update(transform)
    if (this.saveTimer) clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => void dbSet(DATA_KEY, this.data.get()), 250)
  }

  /** Writes pending changes immediately (e.g. before the page is hidden). */
  flush(): void {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer)
      this.saveTimer = null
      void dbSet(DATA_KEY, this.data.get())
    }
  }

  // Brews

  saveNewBrew(brew: Brew, samples: WeightSample[]): void {
    this.cacheSamples(brew.id, samples)
    if (SAFE_ID.test(brew.id)) void dbSet(SAMPLES_PREFIX + brew.id, samples)
    this.update((d) => ({
      ...d,
      brews: [...d.brews, brew],
      beans: brew.beanId ? d.beans.map((b) => (b.id === brew.beanId ? { ...b, remaining: Math.max(0, b.remaining - brew.dose) } : b)) : d.beans,
    }))
  }

  updateBrew(id: string, transform: (brew: Brew) => Brew): void {
    this.update((d) => ({ ...d, brews: d.brews.map((b) => (b.id === id ? transform(b) : b)) }))
  }

  /** Re-assigns the beans of a brew and moves the dose between the bags. */
  assignBean(brewId: string, beanId: string | null): void {
    this.update((d) => {
      const brew = d.brews.find((b) => b.id === brewId)
      if (!brew || brew.beanId === beanId) return d
      return {
        ...d,
        beans: d.beans.map((bean) =>
          bean.id === brew.beanId ? { ...bean, remaining: bean.remaining + brew.dose }
            : bean.id === beanId ? { ...bean, remaining: Math.max(0, bean.remaining - brew.dose) } : bean),
        brews: d.brews.map((b) => (b.id === brewId ? { ...b, beanId } : b)),
      }
    })
  }

  deleteBrew(id: string): void {
    this.update((d) => ({ ...d, brews: d.brews.filter((b) => b.id !== id) }))
    this.samplesCache.delete(id)
    if (SAFE_ID.test(id)) void dbDelete(SAMPLES_PREFIX + id)
  }

  async samples(brewId: string): Promise<WeightSample[]> {
    const cached = this.samplesCache.get(brewId)
    if (cached) return cached
    if (!SAFE_ID.test(brewId)) return []
    const loaded = parseSamples(await dbGet(SAMPLES_PREFIX + brewId))
    this.cacheSamples(brewId, loaded)
    return loaded
  }

  /** Already loaded weight curve, so a screen can render it right away (e.g. after Back). */
  peekSamples(brewId: string): WeightSample[] | undefined {
    return this.samplesCache.get(brewId)
  }

  /** Keeps the most recently used curves in memory (bounded). */
  private cacheSamples(brewId: string, samples: WeightSample[]): void {
    this.samplesCache.delete(brewId)
    this.samplesCache.set(brewId, samples)
    while (this.samplesCache.size > 20) this.samplesCache.delete(this.samplesCache.keys().next().value!)
  }

  // Beans, gear, recipes

  upsertBean(bean: Bean): void {
    this.update((d) => ({ ...d, beans: upsert(d.beans, bean) }))
  }

  deleteBean(id: string): void {
    this.update((d) => ({
      ...d,
      beans: d.beans.filter((b) => b.id !== id),
      brews: d.brews.map((b) => (b.beanId === id ? { ...b, beanId: null } : b)),
    }))
  }

  upsertEquipment(item: Equipment): void {
    this.update((d) => ({ ...d, equipment: upsert(d.equipment, item) }))
  }

  deleteEquipment(id: string): void {
    this.update((d) => ({ ...d, equipment: d.equipment.filter((e) => e.id !== id) }))
  }

  upsertRecipe(recipe: Recipe): void {
    const clean = { ...validatedRecipe(recipe), isCustom: true }
    this.update((d) => ({ ...d, customRecipes: upsert(d.customRecipes, clean) }))
  }

  deleteRecipe(id: string): void {
    this.update((d) => ({ ...d, customRecipes: d.customRecipes.filter((r) => r.id !== id) }))
  }

  // Backup

  /** Everything as one JSON document (app data + weight curves). */
  async exportBackup(): Promise<string> {
    this.flush()
    const samples: Record<string, [number, number][]> = {}
    for (const key of await dbKeys(SAMPLES_PREFIX)) {
      const id = key.slice(SAMPLES_PREFIX.length)
      samples[id] = parseSamples(await dbGet(key)).map((s) => [s.t, s.w])
    }
    return JSON.stringify({ app: 'BrewLog', format: 1, exportedAt: new Date().toISOString(), data: this.data.get(), samples })
  }

  /** Replaces all data with a backup. The file is untrusted: everything is parsed, validated and limited. */
  async importBackup(text: string): Promise<{ brews: number; beans: number }> {
    if (text.length > 50_000_000) throw new Error('This file is too large to be a BrewLog backup.')
    let raw: unknown
    try {
      raw = JSON.parse(text)
    } catch {
      throw new Error('This file is not a valid BrewLog backup.')
    }
    if (typeof raw !== 'object' || raw === null || (raw as { app?: unknown }).app !== 'BrewLog') {
      throw new Error('This file is not a BrewLog backup.')
    }
    const backup = raw as { data?: unknown; samples?: unknown }
    const data = parseAppData(backup.data)
    for (const key of await dbKeys(SAMPLES_PREFIX)) await dbDelete(key)
    this.samplesCache.clear()
    const brewIds = new Set(data.brews.map((b) => b.id))
    if (typeof backup.samples === 'object' && backup.samples !== null) {
      for (const [id, value] of Object.entries(backup.samples as Record<string, unknown>).slice(0, LIMITS.maxBrews)) {
        if (SAFE_ID.test(id) && brewIds.has(id)) await dbSet(SAMPLES_PREFIX + id, parseSamples(value))
      }
    }
    this.data.set(data)
    await dbSet(DATA_KEY, data)
    return { brews: data.brews.length, beans: data.beans.length }
  }
}

function upsert<T extends { id: string }>(list: T[], item: T): T[] {
  return list.some((x) => x.id === item.id) ? list.map((x) => (x.id === item.id ? item : x)) : [...list, item]
}
