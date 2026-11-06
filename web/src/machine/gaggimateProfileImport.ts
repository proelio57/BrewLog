import { blankRecipe } from '../domain/library'
import type { MachineProfileSummary } from '../domain/models'
import type { Recipe, RecipeStep } from '../domain/recipe'
import { LIMITS, validatedRecipe } from '../domain/validation'
import { PROFILE_LABEL_PREFIX } from './gaggimate'

export type { MachineProfileSummary }

export const RECIPE_ID_PREFIX = 'gaggimate-'

type Obj = Record<string, unknown>
const isObj = (v: unknown): v is Obj => typeof v === 'object' && v !== null && !Array.isArray(v)

function num(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null
}

function str(v: unknown): string {
  return typeof v === 'string' ? v : ''
}

function bool(v: unknown): boolean {
  return v === true
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(v, lo), hi)
}

function slug(text: string): string {
  const s = text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
  return s.length > 0 ? s.slice(0, 60) : Math.random().toString(36).slice(2, 10)
}

function formatNum(value: number): string {
  return Number.isInteger(value) ? value.toString() : value.toFixed(1)
}

class Phase {
  readonly name: string
  readonly isPreinfusion: boolean
  readonly duration: number
  pressure: number | null = null
  flow: number | null = null
  power: number | null = null
  holds: 'flow' | 'pressure' | null = null
  readonly volumetricTarget: number | null
  readonly ratioTarget: number | null

  constructor(raw: Obj) {
    this.name = str(raw.name).slice(0, 40)
    this.isPreinfusion = raw.phase === 'preinfusion'
    this.duration = clamp(num(raw.duration) ?? 0, 0, 300)

    if (isObj(raw.pump)) {
      const target = str(raw.pump.target)
      const rawPressure = num(raw.pump.pressure)
      const rawFlow = num(raw.pump.flow)
      const p = rawPressure != null && rawPressure >= 0 ? clamp(rawPressure, 0, 15) : null
      const fl = rawFlow != null && rawFlow >= 0 ? clamp(rawFlow, 0, 15) : null
      const targetVal = target === 'flow' ? rawFlow : rawPressure
      if (targetVal != null && targetVal < 0) {
        this.holds = target === 'flow' ? 'flow' : 'pressure'
      }

      if (target === 'flow') {
        this.flow = fl
        this.pressure = p != null && p > 0 ? p : null
      } else {
        this.pressure = p
      }
    } else {
      const pwr = num(raw.pump)
      if (pwr != null) {
        this.power = clamp(pwr, 0, 100)
      }
    }

    const targets = Array.isArray(raw.targets) ? raw.targets : []
    const targetValue = (type: string): number | null => {
      for (const t of targets) {
        if (isObj(t) && t.type === type) {
          const v = num(t.value)
          if (v != null && v > 0) return v
        }
      }
      return null
    }
    this.volumetricTarget = targetValue('volumetric')
    this.ratioTarget = targetValue('ratio')
  }

  get summary(): string {
    const parts = [this.name.length > 0 ? this.name : this.isPreinfusion ? 'Pre-infusion' : 'Brew']
    if (this.duration > 0) parts.push(`${formatNum(this.duration)} s`)
    if (this.holds != null) {
      parts.push(`hold ${this.holds}`)
    } else if (this.flow != null) {
      parts.push(`${formatNum(this.flow)} ml/s` + (this.pressure != null ? `, max ${formatNum(this.pressure)} bar` : ''))
    } else if (this.pressure != null) {
      parts.push(`${formatNum(this.pressure)} bar`)
    } else if (this.power != null) {
      parts.push(`pump ${formatNum(this.power)} %`)
    }

    if (this.volumetricTarget != null) {
      parts.push(`to ${formatNum(this.volumetricTarget)} g`)
    } else if (this.ratioTarget != null) {
      parts.push(`to 1:${formatNum(this.ratioTarget)}`)
    }
    return parts.join(' · ')
  }
}

function isProfile(v: unknown): v is Obj {
  if (!isObj(v)) return false
  if (!Array.isArray(v.phases)) return false
  if (typeof v.label !== 'string') return false
  // BrewLog recipes have "steps", GaggiMate profiles have "label" and "phases".
  return v.steps === undefined
}

export const GaggiMateProfileImport = {
  /** True if the JSON is one GaggiMate profile, a list of them or `{ "profiles": [...] }`. */
  looksLikeProfiles(value: unknown): boolean {
    if (isObj(value)) {
      if (Array.isArray(value.profiles)) {
        return value.profiles.length > 0 && value.profiles.every((it) => isProfile(it))
      }
      return isProfile(value)
    }
    if (Array.isArray(value)) {
      return value.length > 0 && value.every((it) => isProfile(it))
    }
    return false
  },

  /** All usable profiles in the JSON as recipes. Utility profiles (flush, descale) are left out. */
  recipes(value: unknown): Recipe[] {
    const list: unknown[] =
      isObj(value) && Array.isArray(value.profiles)
        ? value.profiles
        : isObj(value)
          ? [value]
          : Array.isArray(value)
            ? value
            : []
    return list
      .slice(0, 200)
      .filter(isObj)
      .map((it) => GaggiMateProfileImport.recipe(it))
      .filter((r): r is Recipe => r !== null)
  },

  /**
   * The machine's `res:profiles:list` answer for the profile picker: selected first, then favorites,
   * then the rest, each in the machine's order. Utility profiles and entries without an id are left out.
   */
  summaries(response: unknown): MachineProfileSummary[] {
    if (!isObj(response) || !Array.isArray(response.profiles)) return []
    const list = response.profiles.slice(0, 200).filter(isObj)
    const all: MachineProfileSummary[] = []
    for (const profile of list) {
      if (bool(profile.utility)) continue
      const id = str(profile.id).trim()
      if (!id) continue
      let label = str(profile.label).slice(0, LIMITS.maxNameLength).trim()
      if (!label) continue
      const isBrewLogs = label.startsWith(PROFILE_LABEL_PREFIX)
      if (isBrewLogs) label = label.slice(PROFILE_LABEL_PREFIX.length)
      all.push({
        id,
        label,
        isSelected: bool(profile.selected),
        isFavorite: bool(profile.favorite),
        isBrewLogs,
        recipe: GaggiMateProfileImport.recipe(profile),
      })
    }
    return [
      ...all.filter((it) => it.isSelected),
      ...all.filter((it) => !it.isSelected && it.isFavorite),
      ...all.filter((it) => !it.isSelected && !it.isFavorite),
    ]
  },

  /** One profile as an espresso recipe, or null if it has no phases or is a utility profile. */
  recipe(profile: Obj): Recipe | null {
    if (bool(profile.utility)) return null
    if (!Array.isArray(profile.phases) || profile.phases.length === 0) return null
    let label = str(profile.label).trim()
    if (!label) return null
    if (label.startsWith(PROFILE_LABEL_PREFIX)) label = label.slice(PROFILE_LABEL_PREFIX.length)

    const phases = profile.phases
      .slice(0, LIMITS.maxSteps)
      .filter(isObj)
      .map((p) => new Phase(p))
    if (phases.length === 0) return null

    const dose = clamp(num(profile.dose) ?? 18.0, 5.0, 40.0)
    // A weight target wins; otherwise a ratio target (yield = dose * ratio); otherwise 1:2.
    const lastWeight = phases.map((it) => it.volumetricTarget).filter((it): it is number => it !== null).pop()
    const lastRatioVal = phases.map((it) => it.ratioTarget).filter((it): it is number => it !== null).pop()
    const lastRatio = lastRatioVal != null ? lastRatioVal * dose : undefined

    const yieldRaw = lastWeight ?? lastRatio
    const yieldGrams =
      yieldRaw != null
        ? Math.round(clamp(yieldRaw, 5.0, 200.0) * 10) / 10
        : Math.round(dose * 20) / 10 // to 0.1 g, not whole grams

    const preinfusion = phases.filter((it) => it.isPreinfusion).reduce((acc, it) => acc + it.duration, 0)
    const total = phases.reduce((acc, it) => acc + it.duration, 0)
    const hasWeightTarget = phases.some((it) => it.volumetricTarget != null || it.ratioTarget != null)
    const time = Math.round(clamp(hasWeightTarget ? Math.min(total, preinfusion + 25.0) : total, 15.0, 120.0))

    const brewPressures = phases.filter((it) => !it.isPreinfusion).map((it) => it.pressure).filter((it): it is number => it !== null)
    const allPressures = phases.map((it) => it.pressure).filter((it): it is number => it !== null)
    const pressure = (brewPressures.length > 0 ? Math.max(...brewPressures) : allPressures.length > 0 ? Math.max(...allPressures) : 9.0)

    const steps: RecipeStep[] = []
    if (preinfusion >= 1.0) {
      steps.push({
        kind: 'preinfuse',
        time: 0,
        target: null,
        valve: null,
        note: phases.filter((it) => it.isPreinfusion).map((it) => it.summary).join(', '),
      })
    }
    steps.push({
      kind: 'extract',
      time: preinfusion >= 1.0 ? Math.round(preinfusion) : 0,
      target: yieldGrams,
      valve: null,
      note: phases.filter((it) => !it.isPreinfusion).map((it) => it.summary).join(', '),
    })

    const id = str(profile.id).slice(0, 60).trim() || slug(label)
    const description = str(profile.description).trim()
    const blank = blankRecipe()

    const recipe: Recipe = {
      id: RECIPE_ID_PREFIX + id,
      name: label,
      author: 'GaggiMate',
      method: 'espresso',
      summary: description || 'Imported from a GaggiMate profile.',
      tasteNotes: '',
      taste: blank.taste,
      dose,
      water: yieldGrams,
      temperature: clamp(num(profile.temperature) ?? 93.0, 80.0, 100.0),
      grind: '',
      targetTime: time,
      flowMin: 1.0,
      flowMax: 2.5,
      steps,
      tips: phases.map((p, idx) => `Phase ${idx + 1}: ${p.summary}`),
      isCustom: true,
      pressure: clamp(pressure, 1.0, 12.0),
    }

    return validatedRecipe(recipe)
  },
}
