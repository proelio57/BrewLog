import { newId } from './format'
import {
  type AppData, type Bean, type Brew, type Equipment, type GrinderSpec, type WeightSample,
  EQUIPMENT_TYPES, FILTER_FLOWS, GRIND_UNITS, PROCESS_METHODS, ROAST_LEVELS, TASTE_FEEDBACK, defaultGrinderSpec,
} from './models'
import { BREW_METHODS, STEP_KINDS, isPour, type Recipe, type RecipeStep } from './recipe'

// Port of RecipeValidation.swift / Validation.kt, plus defensive parsing of stored and imported data.
// Everything typed by the user, read from storage or imported from a backup file is untrusted:
// it is type-checked, sanitized and clamped, so it can never produce NaN timers, giant allocations or broken UI.

export const LIMITS = {
  maxNameLength: 80,
  maxShortText: 200,
  maxLongText: 2_000,
  maxSteps: 30,
  maxTips: 20,
  maxBrewSeconds: 1_800,
  maxDose: 150,
  maxWater: 3_000,
  maxBagWeight: 10_000,
  maxBrews: 10_000,
  maxBeans: 1_000,
  maxEquipment: 1_000,
  maxRecipes: 500,
  maxSamples: 18_010,
} as const

const CONTROL_OR_FORMAT = /[\p{Cc}\p{Cf}]/gu

/** Removes control/format characters (keeps newlines), trims and limits the length. */
export function sanitized(text: string, maxLength: number): string {
  const cleaned = text.replace(CONTROL_OR_FORMAT, (c) => (c === '\n' ? c : '')).trim()
  return cleaned.length > maxLength ? cleaned.slice(0, maxLength) : cleaned
}

/** Clamps to a range and maps NaN/∞ to the lower bound. */
export function clamped(value: number, lower: number, upper: number): number {
  if (!Number.isFinite(value) || lower > upper) return lower
  return Math.min(Math.max(value, lower), upper)
}

/** Returns a copy with every field sanitized and clamped to sane ranges. */
export function validatedRecipe(recipe: Recipe): Recipe {
  const water = clamped(recipe.water, 10, LIMITS.maxWater)
  const flowMin = clamped(recipe.flowMin, 0.5, 30)
  const flowMax = clamped(recipe.flowMax, flowMin + 0.5, 40)
  const clampedSteps: RecipeStep[] = recipe.steps.slice(0, LIMITS.maxSteps).map((step) => {
    const note = step.note != null ? sanitized(step.note, LIMITS.maxShortText) : ''
    return {
      kind: step.kind,
      time: clamped(step.time, 0, LIMITS.maxBrewSeconds),
      target: isPour(step.kind) ? clamped(step.target ?? 0, 0, water * 1.5) : null,
      valve: step.valve ?? null,
      note: note || null,
    }
  })
  // Stable sort by time, then make cumulative pour targets non-decreasing.
  const sorted = clampedSteps.map((step, index) => ({ step, index }))
    .sort((a, b) => a.step.time - b.step.time || a.index - b.index)
    .map((entry) => entry.step)
  let running = 0
  const steps = sorted.map((step) => {
    if (!isPour(step.kind)) return step
    const target = Math.max(step.target ?? 0, running)
    running = target
    return { ...step, target }
  })
  const lastStep = steps.length ? steps[steps.length - 1].time : 0
  let targetTime = clamped(recipe.targetTime, 10, LIMITS.maxBrewSeconds)
  if (targetTime < lastStep) targetTime = Math.min(lastStep + 30, LIMITS.maxBrewSeconds)
  const level = (v: number) => Math.min(Math.max(Math.round(Number.isFinite(v) ? v : 3), 1), 5)

  return {
    ...recipe,
    id: sanitized(recipe.id, 120) || 'custom-' + newId(),
    name: sanitized(recipe.name, LIMITS.maxNameLength) || 'Untitled recipe',
    author: sanitized(recipe.author, LIMITS.maxNameLength),
    summary: sanitized(recipe.summary, LIMITS.maxLongText),
    tasteNotes: sanitized(recipe.tasteNotes, LIMITS.maxLongText),
    grind: sanitized(recipe.grind, LIMITS.maxShortText),
    dose: clamped(recipe.dose, 1, LIMITS.maxDose),
    water,
    temperature: clamped(recipe.temperature, 0, 100),
    flowMin,
    flowMax,
    taste: {
      acidity: level(recipe.taste.acidity),
      sweetness: level(recipe.taste.sweetness),
      body: level(recipe.taste.body),
      clarity: level(recipe.taste.clarity),
    },
    steps,
    targetTime,
    tips: recipe.tips.slice(0, LIMITS.maxTips).map((tip) => sanitized(tip, LIMITS.maxShortText)).filter(Boolean),
  }
}

// MARK: - Parsing untrusted data

type Obj = Record<string, unknown>
const isObj = (v: unknown): v is Obj => typeof v === 'object' && v !== null && !Array.isArray(v)
const str = (v: unknown, max: number, fallback = ''): string => (typeof v === 'string' ? sanitized(v, max) : fallback)
const num = (v: unknown, lo: number, hi: number, fallback: number): number =>
  typeof v === 'number' && Number.isFinite(v) ? clamped(v, lo, hi) : fallback
const optNum = (v: unknown, lo: number, hi: number): number | null =>
  typeof v === 'number' && Number.isFinite(v) ? clamped(v, lo, hi) : null
const bool = (v: unknown, fallback: boolean): boolean => (typeof v === 'boolean' ? v : fallback)
function oneOf<T extends string>(v: unknown, allowed: readonly T[], fallback: T): T {
  return allowed.includes(v as T) ? (v as T) : fallback
}
function optOneOf<T extends string>(v: unknown, allowed: readonly T[]): T | null {
  return allowed.includes(v as T) ? (v as T) : null
}
/** Only simple ids (letters, digits, -, _): they are also used as storage keys. */
const id = (v: unknown): string => (typeof v === 'string' && /^[A-Za-z0-9_-]{1,120}$/.test(v) ? v : newId())
const optId = (v: unknown): string | null => (typeof v === 'string' && /^[A-Za-z0-9_-]{1,120}$/.test(v) ? v : null)
const time = (v: unknown): number => num(v, 0, 4_102_444_800_000, Date.now())

export function parseRecipe(raw: unknown): Recipe | null {
  if (!isObj(raw) || !Array.isArray(raw.steps)) return null
  const taste = isObj(raw.taste) ? raw.taste : {}
  const steps: RecipeStep[] = raw.steps.slice(0, LIMITS.maxSteps).filter(isObj).map((s) => ({
    kind: oneOf(s.kind, STEP_KINDS, 'pour'),
    time: num(s.time, 0, LIMITS.maxBrewSeconds, 0),
    target: optNum(s.target, 0, LIMITS.maxWater * 1.5),
    valve: optOneOf(s.valve, ['open', 'closed'] as const),
    note: typeof s.note === 'string' ? s.note : null,
  }))
  return validatedRecipe({
    id: typeof raw.id === 'string' ? raw.id : 'custom-' + newId(),
    name: str(raw.name, LIMITS.maxNameLength),
    author: str(raw.author, LIMITS.maxNameLength),
    method: oneOf(raw.method, BREW_METHODS, 'v60'),
    summary: str(raw.summary, LIMITS.maxLongText),
    tasteNotes: str(raw.tasteNotes, LIMITS.maxLongText),
    taste: {
      acidity: num(taste.acidity, 1, 5, 3), sweetness: num(taste.sweetness, 1, 5, 3),
      body: num(taste.body, 1, 5, 3), clarity: num(taste.clarity, 1, 5, 3),
    },
    dose: num(raw.dose, 1, LIMITS.maxDose, 15),
    water: num(raw.water, 10, LIMITS.maxWater, 250),
    temperature: num(raw.temperature, 0, 100, 94),
    grind: str(raw.grind, LIMITS.maxShortText),
    targetTime: num(raw.targetTime, 10, LIMITS.maxBrewSeconds, 180),
    flowMin: num(raw.flowMin, 0.5, 30, 3),
    flowMax: num(raw.flowMax, 1, 40, 8),
    steps,
    tips: Array.isArray(raw.tips) ? raw.tips.filter((t): t is string => typeof t === 'string') : [],
    isCustom: typeof raw.isCustom === 'boolean' ? raw.isCustom : null,
  })
}

export function parseGrinderSpec(raw: unknown): GrinderSpec {
  if (!isObj(raw)) return defaultGrinderSpec()
  const step = num(raw.step, 0.01, 100, 1)
  return {
    unit: oneOf(raw.unit, GRIND_UNITS, 'clicks'),
    step,
    adjustStep: Math.max(num(raw.adjustStep, 0.01, 100, 2), step),
    finerIsLower: bool(raw.finerIsLower, true),
    rangeNote: str(raw.rangeNote, LIMITS.maxShortText),
  }
}

export function parseBean(raw: unknown): Bean | null {
  if (!isObj(raw)) return null
  const name = str(raw.name, LIMITS.maxNameLength)
  if (!name) return null
  return {
    id: id(raw.id), name,
    roaster: str(raw.roaster, LIMITS.maxNameLength),
    origin: str(raw.origin, LIMITS.maxNameLength),
    varietal: str(raw.varietal, LIMITS.maxNameLength),
    process: oneOf(raw.process, PROCESS_METHODS, 'washed'),
    roastLevel: oneOf(raw.roastLevel, ROAST_LEVELS, 'light'),
    roastDate: raw.roastDate == null ? null : Math.min(time(raw.roastDate), Date.now()),
    tastingNotes: str(raw.tastingNotes, LIMITS.maxLongText),
    notes: str(raw.notes, LIMITS.maxLongText),
    bagWeight: num(raw.bagWeight, 0, LIMITS.maxBagWeight, 250),
    remaining: num(raw.remaining, 0, LIMITS.maxBagWeight, 250),
    isArchived: bool(raw.isArchived, false),
    createdAt: time(raw.createdAt),
  }
}

export function parseEquipment(raw: unknown): Equipment | null {
  if (!isObj(raw)) return null
  const name = str(raw.name, LIMITS.maxNameLength)
  if (!name) return null
  return {
    id: id(raw.id), name,
    type: oneOf(raw.type, EQUIPMENT_TYPES, 'brewer'),
    notes: str(raw.notes, LIMITS.maxLongText),
    method: optOneOf(raw.method, BREW_METHODS),
    filterFlow: optOneOf(raw.filterFlow, FILTER_FLOWS),
    idealRoast: optOneOf(raw.idealRoast, ROAST_LEVELS),
    grinder: parseGrinderSpec(raw.grinder),
    createdAt: time(raw.createdAt),
  }
}

export function parseBrew(raw: unknown): Brew | null {
  if (!isObj(raw)) return null
  return {
    id: id(raw.id),
    date: time(raw.date),
    recipeId: str(raw.recipeId, 120),
    recipeName: str(raw.recipeName, LIMITS.maxNameLength, 'Brew'),
    recipe: raw.recipe == null ? null : parseRecipe(raw.recipe),
    dose: num(raw.dose, 0, LIMITS.maxDose, 0),
    targetWater: num(raw.targetWater, 0, LIMITS.maxWater, 0),
    finalWeight: num(raw.finalWeight, 0, LIMITS.maxWater * 2, 0),
    totalTime: num(raw.totalTime, 0, LIMITS.maxBrewSeconds, 0),
    waterTemp: num(raw.waterTemp, 0, 100, 0),
    grindSetting: str(raw.grindSetting, LIMITS.maxNameLength),
    grindValue: optNum(raw.grindValue, 0, 10_000),
    suggestedGrind: optNum(raw.suggestedGrind, 0, 10_000),
    brewerId: optId(raw.brewerId),
    brewerName: str(raw.brewerName, LIMITS.maxNameLength),
    grinderId: optId(raw.grinderId),
    grinderName: str(raw.grinderName, LIMITS.maxNameLength),
    grinderSpec: raw.grinderSpec == null ? null : parseGrinderSpec(raw.grinderSpec),
    filterId: optId(raw.filterId),
    filterName: str(raw.filterName, LIMITS.maxNameLength),
    filterFlow: optOneOf(raw.filterFlow, FILTER_FLOWS),
    filterIdealRoast: optOneOf(raw.filterIdealRoast, ROAST_LEVELS),
    beanId: optId(raw.beanId),
    usedScale: bool(raw.usedScale, false),
    rating: Math.round(num(raw.rating, 0, 5, 0)),
    feedback: Array.isArray(raw.feedback)
      ? [...new Set(raw.feedback.filter((f): f is (typeof TASTE_FEEDBACK)[number] => TASTE_FEEDBACK.includes(f as never)))]
      : [],
    notes: str(raw.notes, LIMITS.maxLongText),
  }
}

/** Parses and limits stored or imported app data. Unknown fields are dropped. */
export function parseAppData(raw: unknown): AppData {
  const data = isObj(raw) ? raw : {}
  const list = <T>(v: unknown, max: number, parse: (x: unknown) => T | null): T[] =>
    Array.isArray(v) ? v.slice(0, max).map(parse).filter((x): x is T => x !== null) : []
  const unique = <T extends { id: string }>(items: T[]): T[] => {
    const seen = new Set<string>()
    return items.filter((item) => (seen.has(item.id) ? false : (seen.add(item.id), true)))
  }
  return {
    version: 1,
    beans: unique(list(data.beans, LIMITS.maxBeans, parseBean)),
    equipment: unique(list(data.equipment, LIMITS.maxEquipment, parseEquipment)),
    brews: unique(list(data.brews, LIMITS.maxBrews, parseBrew)),
    customRecipes: list(data.customRecipes, LIMITS.maxRecipes, parseRecipe).map((r) => ({ ...r, isCustom: true })),
  }
}

/** Weight curves: arrays of {t, w} (or [t, w]) numbers, capped and clamped. */
export function parseSamples(raw: unknown): WeightSample[] {
  if (!Array.isArray(raw)) return []
  const out: WeightSample[] = []
  for (const entry of raw.slice(0, LIMITS.maxSamples)) {
    const t = Array.isArray(entry) ? entry[0] : isObj(entry) ? entry.t : undefined
    const w = Array.isArray(entry) ? entry[1] : isObj(entry) ? entry.w : undefined
    if (typeof t === 'number' && typeof w === 'number' && Number.isFinite(t) && Number.isFinite(w)) {
      out.push({ t: clamped(t, 0, LIMITS.maxBrewSeconds), w: clamped(w, -3_000, 5_000) })
    }
  }
  return out
}
