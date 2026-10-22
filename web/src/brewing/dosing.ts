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
