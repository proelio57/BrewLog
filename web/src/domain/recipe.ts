import { fmt1, roundHalfAway } from './format'

// Port of Recipe.swift / Recipe.kt. JSON field names are identical, so recipes.json is shared by all platforms.

export type BrewMethod = 'v60' | 'switch' | 'kalita' | 'universal' | 'espresso'
export const BREW_METHODS: BrewMethod[] = ['v60', 'switch', 'kalita', 'universal', 'espresso']
export const METHOD_NAMES: Record<BrewMethod, string> = {
  v60: 'V60',
  switch: 'Hario Switch',
  kalita: 'Flat bottom',
  universal: 'Any pour-over',
  espresso: 'Espresso',
}

export type StepKind = 'bloom' | 'pour' | 'swirl' | 'stir' | 'closeValve' | 'openValve' | 'remove' | 'preinfuse' | 'extract'
export const STEP_KINDS: StepKind[] = ['bloom', 'pour', 'swirl', 'stir', 'closeValve', 'openValve', 'remove', 'preinfuse', 'extract']
export const STEP_TITLES: Record<StepKind, string> = {
  bloom: 'Bloom',
  pour: 'Pour',
  swirl: 'Swirl',
  stir: 'Stir',
  closeValve: 'Close valve',
  openValve: 'Open valve',
  remove: 'Remove dripper',
  preinfuse: 'Pre-infusion',
  extract: 'Extract',
}
/** Steps with a cumulative weight target on the scale. */
export const isPour = (kind: StepKind): boolean => kind === 'bloom' || kind === 'pour' || kind === 'extract'
export const isEspresso = (recipe: { method: BrewMethod } | null | undefined): boolean => recipe?.method === 'espresso'

export type ValveState = 'open' | 'closed'

export interface RecipeStep {
  kind: StepKind
  /** Start time in seconds from brew start. */
  time: number
  /** Cumulative target weight in grams (pours/blooms only). */
  target?: number | null
  valve?: ValveState | null
  note?: string | null
}

export interface TasteProfile {
  acidity: number
  sweetness: number
  body: number
  clarity: number
}

export interface Recipe {
  id: string
  name: string
  author: string
  method: BrewMethod
  summary: string
  /** Plain-language description of how the cup should taste. */
  tasteNotes: string
  taste: TasteProfile
  dose: number
  water: number
  temperature: number
  grind: string
  /** Expected total brew time (incl. drawdown) in seconds. */
  targetTime: number
  /** Healthy average pour rate range in g/s. */
  flowMin: number
  flowMax: number
  steps: RecipeStep[]
  tips: string[]
  isCustom?: boolean | null
  /** Espresso: peak brew pressure in bar the recipe is designed for (e.g. 9, or 6 for turbo shots). */
  pressure?: number | null
}

export const ratio = (recipe: Recipe): number => (recipe.dose > 0 ? recipe.water / recipe.dose : 0)
export const ratioText = (recipe: Recipe): string => `1:${fmt1(ratio(recipe))}`
export const pourSteps = (recipe: Recipe): RecipeStep[] => recipe.steps.filter((s) => isPour(s.kind) && s.target != null)

export function stepHeadline(step: RecipeStep): string {
  if (isPour(step.kind) && step.target != null) {
    const verb = step.kind === 'bloom' ? 'Bloom to' : step.kind === 'extract' ? 'Extract to' : 'Pour to'
    return `${verb} ${roundHalfAway(step.target)} g`
  }
  return STEP_TITLES[step.kind]
}

/** Copy scaled to a new dose. Times stay the same; weights scale with the dose. */
export function scaled(recipe: Recipe, newDose: number): Recipe {
  if (recipe.dose <= 0 || newDose <= 0 || Math.abs(newDose - recipe.dose) <= 0.01) return recipe
  const factor = newDose / recipe.dose
  return {
    ...recipe,
    dose: newDose,
    water: roundHalfAway(recipe.water * factor),
    steps: recipe.steps.map((s) => (s.target != null ? { ...s, target: roundHalfAway(s.target * factor) } : s)),
  }
}

/** Expected cumulative weight over time, used to draw the "ideal" line on charts. */
export function targetCurve(recipe: Recipe): [number, number][] {
  const points: [number, number][] = [[0, 0]]
  let previous = 0
  const idealFlow = Math.max((recipe.flowMin + recipe.flowMax) / 2, 1)
  const pours = pourSteps(recipe)
  pours.forEach((step, offset) => {
    const target = step.target
    if (target == null) return
    const nextStart = offset + 1 < pours.length ? pours[offset + 1].time : recipe.targetTime
    let duration = (target - previous) / idealFlow
    duration = Math.min(duration, Math.max(nextStart - step.time - 1, 1))
    points.push([step.time, previous])
    points.push([step.time + duration, target])
    previous = target
  })
  points.push([recipe.targetTime, previous])
  return points
}
