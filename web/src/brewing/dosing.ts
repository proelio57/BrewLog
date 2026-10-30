import { scaled, type Recipe } from '../domain/recipe'
import { LIMITS } from '../domain/validation'

// Port of BeanDosing.swift: weighing the beans before a brew.

export type DoseStatus = 'empty' | 'under' | 'onTarget' | 'over'

/** ±0.2 g counts as on target: the scale shows 0.1 g and a single bean weighs about 0.15 g. */
export const DOSE_TOLERANCE = 0.2

export function doseStatus(weight: number, dose: number): DoseStatus {
  if (!Number.isFinite(weight) || weight < 0.5) return 'empty'
  if (weight < dose - DOSE_TOLERANCE) return 'under'
  if (weight > dose + DOSE_TOLERANCE) return 'over'
  return 'onTarget'
}

/** 0…1 for the progress bar. */
export function doseProgress(weight: number, dose: number): number {
  if (!(dose > 0) || !Number.isFinite(weight)) return 0
  return Math.min(Math.max(weight / dose, 0), 1)
}

/** The dose to save with the brew: what was weighed (to 0.1 g), or the planned dose when the reading is implausible. */
export function acceptedDose(weight: number, planned: number): number {
  if (!Number.isFinite(weight) || weight < 0.5 || weight > LIMITS.maxDose) return planned
  return Math.round(weight * 10) / 10
}

/** Below this difference the recipe stays as planned; from here on it is scaled to the weighed dose. */
export const RESCALE_THRESHOLD = 0.5

/** The recipe for the weighed dose: scaled (water and pour targets) when it is at least 0.5 g off the plan. */
export const recipeForDose = (recipe: Recipe, dose: number): Recipe =>
  Math.abs(dose - recipe.dose) >= RESCALE_THRESHOLD ? scaled(recipe, dose) : recipe

/**
 * A settled reading: the readings of the last second (at least 4) lie within ±0.2 g. Lifting the cup off or still
 * pouring beans in doesn't count, so "Ready" keeps what was actually weighed. [readings]: [ms, grams].
 */
export function stableWeight(readings: readonly (readonly [number, number])[], nowMs: number): number | null {
  const window = readings.filter(([t]) => nowMs - t <= 1_000).map(([, g]) => g)
  if (window.length < 4 || Math.max(...window) - Math.min(...window) > 2 * DOSE_TOLERANCE) return null
  const mean = window.reduce((a, b) => a + b, 0) / window.length
  return doseStatus(mean, 1) === 'empty' ? null : mean
}
