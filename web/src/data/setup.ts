import { type AppData, type Equipment, type EquipmentType, defaultStartingValue } from '../domain/models'
import { blankRecipe } from '../domain/library'
import { scaled, type Recipe } from '../domain/recipe'
import { recommendGrind } from '../analysis/recommender'
import { Store } from './store'

export type SetupScope = 'filter' | 'espresso'

export interface SetupState {
  recipe: Recipe
  dose: number
  waterTemp: number
  beanId: string | null
  brewerId: string | null
  grinderId: string | null
  filterId: string | null
  waterId: string | null
  grindValue: number | null
  grindText: string
}

/** The brew being configured on the Brew tab. Remembers your last choices. Port of BrewSetup. */
export class BrewSetup {
  readonly state: Store<SetupState>
  /** bean|grinder|recipe for which a history recommendation was last applied (emulates SwiftUI's onChange). */
  lastRecommendationContext: string | null = null
  /** Bean + grinder for which the grind was set explicitly (setup assistant, "Brew again"). */
  private pinnedGrindContext: string | null = null
  private knownGear = new Map<EquipmentType, Set<string>>()
  private readonly lastGrindByGrinder = new Map<string, number>()

  private get storageKey(): string {
    return this.scope === 'espresso' ? 'brewlog.espressoSetup' : 'brewlog.setup'
  }

  constructor(private readonly recipes: () => Recipe[], readonly scope: SetupScope = 'filter') {
    let saved: Record<string, unknown> = {}
    try {
      saved = JSON.parse(localStorage.getItem(this.storageKey) ?? '{}') ?? {}
    } catch {
      saved = {}
    }
    const id = (v: unknown) => (typeof v === 'string' && /^[A-Za-z0-9_-]{1,120}$/.test(v) ? v : null)
    const isEspresso = scope === 'espresso'
    const recipe =
      recipes().find((r) => r.id === saved.recipeId) ??
      recipes().find((r) => (r.method === 'espresso') === isEspresso) ??
      recipes()[0] ??
      blankRecipe()

    const initialGrinderId = id(saved.grinderId)
    let initialGrindValue: number | null = null
    if (initialGrinderId) {
      try {
        const key = `brewlog.${this.scope}.lastGrind.${initialGrinderId}`
        const v = localStorage.getItem(key)
        if (v != null) {
          const num = parseFloat(v)
          if (!isNaN(num)) initialGrindValue = num
        }
      } catch {
        // ignore
      }
    }

    this.state = new Store<SetupState>({
      recipe,
      dose: recipe.dose,
      waterTemp: recipe.temperature,
      beanId: id(saved.beanId),
      brewerId: id(saved.brewerId),
      grinderId: initialGrinderId,
      filterId: id(saved.filterId),
      waterId: id(saved.waterId),
      grindValue: initialGrindValue,
      grindText: '',
    })
  }

  get value(): SetupState {
    return this.state.get()
  }

  patch(patch: Partial<SetupState>): void {
    this.state.update((s) => ({ ...s, ...patch }))
    const s = this.state.get()
    try {
      localStorage.setItem(
        this.storageKey,
        JSON.stringify({
          recipeId: s.recipe.id,
          beanId: s.beanId,
          brewerId: s.brewerId,
          grinderId: s.grinderId,
          filterId: s.filterId,
          waterId: s.waterId,
        }),
      )
    } catch {
      // ignore
    }
  }

  select(recipe: Recipe): void {
    this.patch({ recipe, dose: recipe.dose, waterTemp: recipe.temperature })
  }

  /** Restores a custom recipe chosen last time once the repository has loaded. */
  restore(): void {
    try {
      const saved = JSON.parse(localStorage.getItem(this.storageKey) ?? '{}')
      const recipe = this.recipes().find((r) => r.id === saved?.recipeId)
      if (recipe && recipe.id !== this.value.recipe.id) this.select(recipe)
    } catch {
      // ignore
    }
  }

  get scaledRecipe(): Recipe {
    return scaled(this.value.recipe, this.value.dose)
  }

  private get grindContextKey(): string {
    return `${this.value.beanId ?? '-'}|${this.value.grinderId ?? '-'}`
  }

  /** Sets the grind explicitly so a history recommendation doesn't replace it for the current bean + grinder. */
  pinGrind(value: number | null): void {
    this.patch({ grindValue: value })
    this.pinnedGrindContext = this.grindContextKey
    const gid = this.value.grinderId
    if (gid && value != null) {
      this.lastGrindByGrinder.set(gid, value)
      try {
        localStorage.setItem(`brewlog.${this.scope}.lastGrind.${gid}`, String(value))
      } catch {
        // ignore
      }
    }
  }

  setGrind(value: number | null): void {
    this.pinGrind(value)
  }

  /** Returns the last grind explicitly set on grinder [id], or null if none set. */
  lastGrindFor(id: string): number | null {
    if (this.lastGrindByGrinder.has(id)) {
      return this.lastGrindByGrinder.get(id) ?? null
    }
    try {
      const key = `brewlog.${this.scope}.lastGrind.${id}`
      const v = localStorage.getItem(key)
      if (v != null) {
        const num = parseFloat(v)
        if (!isNaN(num)) {
          this.lastGrindByGrinder.set(id, num)
          return num
        }
      }
    } catch {
      // ignore
    }
    return null
  }

  /**
   * Switches to a grinder without carrying over the numeric grind from the previous grinder.
   * Restores the last set grind for newId, or historical recommendation, or the grinder's default value.
   */
  selectGrinder(
    newId: string | null,
    grinder: Equipment | null,
    brews: AppData['brews'] = [],
  ): void {
    const cleanId = newId && newId.length > 0 ? newId : null
    if (this.value.grinderId === cleanId && this.value.grindValue != null) return
    this.patch({ grinderId: cleanId })
    if (!cleanId || !grinder) {
      this.patch({ grindValue: null })
      this.pinnedGrindContext = null
      this.lastRecommendationContext = null
      return
    }

    // 1. Remembered grind for this grinder
    const remembered = this.lastGrindFor(cleanId)
    if (remembered != null) {
      this.patch({ grindValue: remembered })
      this.pinnedGrindContext = this.grindContextKey
      this.lastRecommendationContext = `${this.value.beanId ?? '-'}|${cleanId}|${this.value.recipe.id}`
      return
    }

    // 2. Recommendation from history
    const rec = recommendGrind(this.value.beanId, grinder, this.value.recipe.id, brews)
    if (rec != null) {
      this.patch({ grindValue: rec.value })
      this.pinnedGrindContext = null
      this.lastRecommendationContext = `${this.value.beanId ?? '-'}|${cleanId}|${this.value.recipe.id}`
      return
    }

    // 3. Fallback: default starting value
    this.patch({ grindValue: defaultStartingValue(grinder.grinder) })
    this.pinnedGrindContext = null
    this.lastRecommendationContext = `${this.value.beanId ?? '-'}|${cleanId}|${this.value.recipe.id}`
  }

  get isGrindPinned(): boolean {
    return this.pinnedGrindContext === this.grindContextKey
  }

  /**
   * After restoring a backup: keeps selections that still exist, otherwise continues with the gear and beans
   * of the latest brew (or the first item of each kind).
   */
  adopt(data: AppData): void {
    const isEspresso = this.scope === 'espresso'
    const matchingBrews = data.brews.filter((b) => (b.recipe?.method === 'espresso') === isEspresso)
    const latest = (matchingBrews.length > 0 ? matchingBrews : data.brews).reduce<AppData['brews'][number] | null>(
      (a, b) => (!a || b.date > a.date ? b : a),
      null,
    )
    const pick = (current: string | null, fromBrew: string | null | undefined, ids: string[]): string | null =>
      current != null && ids.includes(current) ? current : fromBrew != null && ids.includes(fromBrew) ? fromBrew : ids[0] ?? null
    const gear = (type: EquipmentType) =>
      data.equipment
        .filter((e) => e.type === type && (type !== 'brewer' || (e.method === 'espresso') === isEspresso))
        .map((e) => e.id)
    const beans = data.beans.filter((b) => !b.isArchived).sort((a, b) => b.createdAt - a.createdAt).map((b) => b.id)
    const s = this.value
    this.patch({
      brewerId: pick(s.brewerId, latest?.brewerId, gear('brewer')),
      filterId: pick(s.filterId, latest?.filterId, gear('filter')),
      grinderId: pick(s.grinderId, latest?.grinderId, gear('grinder')),
      beanId: pick(s.beanId, latest?.beanId, beans),
      grindValue: null,
    })
    this.lastRecommendationContext = null
  }

  /** Clears selections of deleted gear and auto-selects newly added gear when nothing is selected. */
  reconcileGear(type: EquipmentType, ids: string[]): void {
    const field = type === 'brewer' ? 'brewerId' : type === 'grinder' ? 'grinderId' : type === 'filter' ? 'filterId' : null
    if (!field) return
    const previous = this.knownGear.get(type)
    const current = this.value[field]
    let next = current
    if (next != null && !ids.includes(next)) next = null
    if (next == null && previous) next = ids.find((id) => !previous.has(id)) ?? null
    if (next !== current) this.patch({ [field]: next } as Partial<SetupState>)
    this.knownGear.set(type, new Set(ids))
  }
}
