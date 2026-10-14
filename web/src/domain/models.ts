import { newId, roundHalfAway } from './format'
import type { BrewMethod, Recipe } from './recipe'

// Port of Models.swift / Models.kt.

export type RoastLevel = 'light' | 'mediumLight' | 'medium' | 'mediumDark' | 'dark'
export const ROAST_LEVELS: RoastLevel[] = ['light', 'mediumLight', 'medium', 'mediumDark', 'dark']
export const ROAST_NAMES: Record<RoastLevel, string> = {
  light: 'Light',
  mediumLight: 'Medium-light',
  medium: 'Medium',
  mediumDark: 'Medium-dark',
  dark: 'Dark',
}
/** 0 = lightest, 4 = darkest */
export const roastIndex = (level: RoastLevel): number => ROAST_LEVELS.indexOf(level)

export type ProcessMethod = 'washed' | 'natural' | 'honey' | 'anaerobic' | 'other'
export const PROCESS_METHODS: ProcessMethod[] = ['washed', 'natural', 'honey', 'anaerobic', 'other']
export const PROCESS_NAMES: Record<ProcessMethod, string> = {
  washed: 'Washed', natural: 'Natural', honey: 'Honey', anaerobic: 'Anaerobic', other: 'Other',
}

export type EquipmentType = 'brewer' | 'grinder' | 'kettle' | 'filter' | 'scale' | 'water'
export const EQUIPMENT_TYPES: EquipmentType[] = ['brewer', 'grinder', 'kettle', 'filter', 'scale', 'water']
export const EQUIPMENT_NAMES: Record<EquipmentType, string> = {
  brewer: 'Brewers', grinder: 'Grinders', kettle: 'Kettles', filter: 'Filters', scale: 'Scales', water: 'Water',
}

/** How fast water passes through a filter paper. This has a big effect on drawdown time. */
export type FilterFlow = 'fast' | 'medium' | 'slow'
export const FILTER_FLOWS: FilterFlow[] = ['fast', 'medium', 'slow']
export const FLOW_NAMES: Record<FilterFlow, string> = { fast: 'Fast', medium: 'Medium', slow: 'Slow' }

export type PaperShape = 'cone' | 'flat' | 'chemex'

export type GrindUnit = 'clicks' | 'numbers' | 'dial' | 'microns'
export const GRIND_UNITS: GrindUnit[] = ['clicks', 'numbers', 'dial', 'microns']
export const GRIND_UNIT_NAMES: Record<GrindUnit, string> = { clicks: 'Clicks', numbers: 'Numbers', dial: 'Dial', microns: 'Microns' }
const GRIND_SUFFIX: Record<GrindUnit, string> = { clicks: 'clicks', numbers: '', dial: '', microns: 'µm' }
export const grindSuffix = (unit: GrindUnit): string => GRIND_SUFFIX[unit]

/** A grinder's adjustment scale, so suggestions can be concrete ("try 22 clicks"). */
export interface GrinderSpec {
  unit: GrindUnit
  /** Smallest increment, e.g. 1 click or 0.1 on a dial. */
  step: number
  /** What a sensible small adjustment is for this grinder. */
  adjustStep: number
  /** Most grinders get finer as the number goes down. */
  finerIsLower: boolean
  /** Typical pour-over range, e.g. "20–30 clicks" (informational). */
  rangeNote: string
}

export const defaultGrinderSpec = (): GrinderSpec => ({ unit: 'clicks', step: 1, adjustStep: 2, finerIsLower: true, rangeNote: '' })

const decimalsFor = (spec: GrinderSpec): number => (spec.step < 1 ? (spec.step < 0.1 ? 2 : 1) : 0)

export function formatGrind(spec: GrinderSpec, value: number): string {
  const number = value.toFixed(decimalsFor(spec))
  const suffix = grindSuffix(spec.unit)
  return suffix ? `${number} ${suffix}` : number
}

export function formatGrindDelta(spec: GrinderSpec, delta: number): string {
  const number = Math.abs(delta).toFixed(decimalsFor(spec))
  switch (spec.unit) {
    case 'clicks': return `${number} click${Math.abs(delta) === 1 ? '' : 's'}`
    case 'microns': return `${number} µm`
    default: return number
  }
}

/** Moves a value by adjustment steps toward finer or coarser, snapped to the grinder's step. */
export function adjustGrind(spec: GrinderSpec, value: number, coarser: boolean, multiplier = 1): number {
  const delta = spec.adjustStep * multiplier
  const signed = coarser === spec.finerIsLower ? delta : -delta
  const snapped = roundHalfAway((value + signed) / spec.step) * spec.step
  return Math.max(0, snapped)
}

export interface WeightSample {
  /** Seconds since brew start. */
  t: number
  /** Grams on the scale. */
  w: number
}

export type TasteFeedback = 'perfect' | 'sour' | 'bitter' | 'weak' | 'strong' | 'astringent' | 'flat'
export const TASTE_FEEDBACK: TasteFeedback[] = ['perfect', 'sour', 'bitter', 'weak', 'strong', 'astringent', 'flat']
export const FEEDBACK_INFO: Record<TasteFeedback, { title: string; subtitle: string }> = {
  perfect: { title: 'Perfect', subtitle: 'Sweet, balanced, would brew again' },
  sour: { title: 'Too sour', subtitle: 'Sharp, salty, thin, short finish' },
  bitter: { title: 'Too bitter', subtitle: 'Harsh, burnt, lingering bitterness' },
  weak: { title: 'Too weak', subtitle: 'Watery, lacking flavour' },
  strong: { title: 'Too strong', subtitle: 'Heavy, intense, muddy' },
  astringent: { title: 'Dry / astringent', subtitle: 'Drying, rough, mouth-puckering' },
  flat: { title: 'Flat / dull', subtitle: 'Lifeless, hollow, no sparkle' },
}

export interface Bean {
  id: string
  name: string
  roaster: string
  origin: string
  varietal: string
  process: ProcessMethod
  roastLevel: RoastLevel
  /** Epoch millis. */
  roastDate: number | null
  tastingNotes: string
  notes: string
  bagWeight: number
  remaining: number
  isArchived: boolean
  createdAt: number
}

export const newBean = (fields: Partial<Bean> = {}): Bean => ({
  id: newId(), name: '', roaster: '', origin: '', varietal: '', process: 'washed', roastLevel: 'light', roastDate: null,
  tastingNotes: '', notes: '', bagWeight: 250, remaining: 250, isArchived: false, createdAt: Date.now(), ...fields,
})

export const beanDisplayName = (bean: Bean): string => (bean.roaster ? `${bean.name} · ${bean.roaster}` : bean.name)

export const daysOffRoast = (bean: Bean, now = Date.now()): number | null =>
  bean.roastDate == null ? null : Math.floor((now - bean.roastDate) / 86_400_000)

export interface Equipment {
  id: string
  name: string
  type: EquipmentType
  notes: string
  /** Brewers only. */
  method: BrewMethod | null
  /** Filters only: flow speed of the paper. */
  filterFlow: FilterFlow | null
  /** Filters only: roast level the paper is designed for (e.g. CAFEC roast-specific papers). */
  idealRoast: RoastLevel | null
  /** Grinders only: adjustment scale. */
  grinder: GrinderSpec
  createdAt: number
}

export function equipmentSubtitle(item: Equipment): string {
  switch (item.type) {
    case 'filter':
      return [item.filterFlow && `${item.filterFlow[0].toUpperCase()}${item.filterFlow.slice(1)} flow`,
        item.idealRoast && `for ${ROAST_NAMES[item.idealRoast].toLowerCase()} roasts`].filter(Boolean).join(' · ')
    case 'grinder':
      return `Adjust in steps of ${formatGrindDelta(item.grinder, item.grinder.adjustStep)}` +
        (item.grinder.rangeNote ? ` · pour-over ${item.grinder.rangeNote}` : '')
    case 'brewer': {
      const names: Record<string, string> = { v60: 'V60', switch: 'Hario Switch', kalita: 'Flat bottom', universal: 'Any pour-over' }
      return item.method ? names[item.method] : ''
    }
    default:
      return item.notes
  }
}

export interface Brew {
  id: string
  date: number
  recipeId: string
  recipeName: string
  /** Snapshot of the (scaled) recipe used. */
  recipe: Recipe | null
  dose: number
  targetWater: number
  finalWeight: number
  totalTime: number
  waterTemp: number
  /** Free-text grind (used when no grinder is selected). */
  grindSetting: string
  /** Numeric grind on the selected grinder's scale. */
  grindValue: number | null
  /** Grind suggested by the analysis after reviewing. Pre-filled next time. */
  suggestedGrind: number | null
  brewerId: string | null
  brewerName: string
  grinderId: string | null
  grinderName: string
  grinderSpec: GrinderSpec | null
  filterId: string | null
  filterName: string
  filterFlow: FilterFlow | null
  filterIdealRoast: RoastLevel | null
  beanId: string | null
  usedScale: boolean
  rating: number
  feedback: TasteFeedback[]
  notes: string
}

export const brewRatio = (brew: Brew): number => (brew.dose > 0 ? brew.finalWeight / brew.dose : 0)
export const isReviewed = (brew: Brew): boolean => brew.rating > 0 || brew.feedback.length > 0
export const grindDisplay = (brew: Brew): string =>
  brew.grindValue != null ? formatGrind(brew.grinderSpec ?? defaultGrinderSpec(), brew.grindValue) : brew.grindSetting

/** Everything the app stores (weight curves are stored separately, one record per brew). */
export interface AppData {
  version: number
  beans: Bean[]
  equipment: Equipment[]
  brews: Brew[]
  customRecipes: Recipe[]
}

export const emptyAppData = (): AppData => ({ version: 1, beans: [], equipment: [], brews: [], customRecipes: [] })

export type PingLeadMode = 'auto' | 'fixed'

export interface AppSettings {
  autoStartThreshold: number
  pingLeadMode: PingLeadMode
  pingLeadGrams: number
  reactionTime: number
  soundEnabled: boolean
  hapticsEnabled: boolean
  soundVolume: number
  silentModeSound: boolean
  countdownTicks: boolean
  finishPing: boolean
  keepAwake: boolean
  onboardingDone: boolean
  setupBannerDismissed: boolean
  quickWeighAutoStart: boolean
  chartShowsFlow: boolean
  demoScale: boolean
}

export const DEFAULT_SETTINGS: AppSettings = {
  autoStartThreshold: 1.5,
  pingLeadMode: 'auto',
  pingLeadGrams: 3,
  reactionTime: 0.6,
  soundEnabled: true,
  hapticsEnabled: true,
  soundVolume: 0.8,
  silentModeSound: true,
  countdownTicks: false,
  finishPing: true,
  keepAwake: true,
  onboardingDone: false,
  setupBannerDismissed: false,
  quickWeighAutoStart: true,
  chartShowsFlow: true,
  demoScale: false,
}
