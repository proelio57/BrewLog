import type { AppData, EquipmentType } from '../domain/models'
import { blankRecipe } from '../domain/library'
import { scaled, type Recipe } from '../domain/recipe'
import { Store } from './store'

const KEY = 'brewlog.setup'

export interface SetupState {
  recipe: Recipe
  dose: number
  waterTemp: number
  beanId: string | null
  brewerId: string | null
  grinderId: string | null
  filterId: string | null
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

  constructor(private readonly recipes: () => Recipe[]) {
    let saved: Record<string, unknown> = {}
    try {
      saved = JSON.parse(localStorage.getItem(KEY) ?? '{}') ?? {}
    } catch {
      saved = {}
    }
    const id = (v: unknown) => (typeof v === 'string' && /^[A-Za-z0-9_-]{1,120}$/.test(v) ? v : null)
    const recipe = recipes().find((r) => r.id === saved.recipeId) ?? recipes()[0] ?? blankRecipe()
    this.state = new Store<SetupState>({
      recipe, dose: recipe.dose, waterTemp: recipe.temperature,
      beanId: id(saved.beanId), brewerId: id(saved.brewerId), grinderId: id(saved.grinderId), filterId: id(saved.filterId),
      grindValue: null, grindText: '',
    })
  }

  get value(): SetupState {
    return this.state.get()
  }

  patch(patch: Partial<SetupState>): void {
    this.state.update((s) => ({ ...s, ...patch }))
    const s = this.state.get()
    try {
      localStorage.setItem(KEY, JSON.stringify({
        recipeId: s.recipe.id, beanId: s.beanId, brewerId: s.brewerId, grinderId: s.grinderId, filterId: s.filterId,
      }))
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
      const saved = JSON.parse(localStorage.getItem(KEY) ?? '{}')
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
  }

  get isGrindPinned(): boolean {
    return this.pinnedGrindContext === this.grindContextKey
  }

  /**
   * After restoring a backup: keeps selections that still exist, otherwise continues with the gear and beans
   * of the latest brew (or the first item of each kind).
   */
  adopt(data: AppData): void {
    const latest = data.brews.reduce<AppData['brews'][number] | null>((a, b) => (!a || b.date > a.date ? b : a), null)
    const pick = (current: string | null, fromBrew: string | null | undefined, ids: string[]): string | null =>
      current != null && ids.includes(current) ? current : fromBrew != null && ids.includes(fromBrew) ? fromBrew : ids[0] ?? null
    const gear = (type: EquipmentType) => data.equipment.filter((e) => e.type === type).map((e) => e.id)
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
