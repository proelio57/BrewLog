import { clamped } from './validation'

export interface WaterProfilePreset {
  name: string
  hardness: number
  alkalinity: number
  note: string
}

export interface WaterRecipeCalculations {
  epsomGrams: number
  calciumChlorideGrams: number
  bakingSodaGrams: number
  hardnessConcentrateGrams: number
  calciumConcentrateGrams: number
  bufferConcentrateGrams: number
  distilledGrams: number
}

/**
 * Brewing water made from distilled / reverse-osmosis water and minerals. Hardness (GH) and alkalinity (KH) are in
 * mg/L (ppm) as CaCO3. Epsom salt (MgSO4·7H2O) and calcium chloride (CaCl2·2H2O) for hardness, baking soda (NaHCO3)
 * for the buffer. Concentrates follow Barista Hustle: 1000 ppm each, so 1 g per litre adds 1 ppm.
 * Port of Tools/WaterChemistry.swift / WaterChemistry.kt.
 */
export const WaterChemistry = {
  /** Milligrams of mineral per litre for 1 mg/L as CaCO3 (molar mass ratios; bicarbonate counts half). */
  EPSOM_PER_PPM: 246.47 / 100.09,
  CALCIUM_CHLORIDE_PER_PPM: 147.01 / 100.09,
  BAKING_SODA_PER_PPM: (2 * 84.007) / 100.09,

  MAX_PPM: 500.0,
  MAX_LITRES: 50.0,

  presets: [
    { name: 'SCA standard', hardness: 68.0, alkalinity: 40.0, note: 'The SCA target for brewing water: 68 ppm hardness, 40 ppm alkalinity.' },
    { name: 'Rao', hardness: 76.0, alkalinity: 50.0, note: "Close to Scott Rao's recommendation. A bit more buffer, rounder and less bright." },
    { name: 'Barista Hustle', hardness: 81.0, alkalinity: 40.0, note: "Barista Hustle's original recipe. Lots of hardness for sweetness and body." },
    { name: 'Hendon', hardness: 100.0, alkalinity: 31.0, note: "Centre of Hendon's and Colonna-Dashwood's ideal zone. High hardness, low buffer, very bright." },
    { name: 'World of Coffee Budapest', hardness: 51.0, alkalinity: 40.0, note: 'Competition water. Balanced and clean.' },
    { name: 'Melbourne', hardness: 24.0, alkalinity: 12.0, note: 'Very soft, like Melbourne tap water. Clear and delicate, great for light roasts.' },
  ] as WaterProfilePreset[],

  calculate(hardness: number, alkalinity: number, litres: number, magnesiumShare = 1.0): WaterRecipeCalculations {
    const h = clamped(hardness, 0, WaterChemistry.MAX_PPM)
    const a = clamped(alkalinity, 0, WaterChemistry.MAX_PPM)
    const l = clamped(litres, 0, WaterChemistry.MAX_LITRES)
    const mg = clamped(magnesiumShare, 0, 1)

    const epsomGrams = (h * mg * WaterChemistry.EPSOM_PER_PPM * l) / 1000
    const calciumChlorideGrams = (h * (1 - mg) * WaterChemistry.CALCIUM_CHLORIDE_PER_PPM * l) / 1000
    const bakingSodaGrams = (a * WaterChemistry.BAKING_SODA_PER_PPM * l) / 1000

    const hardnessConcentrateGrams = h * mg * l
    const calciumConcentrateGrams = h * (1 - mg) * l
    const bufferConcentrateGrams = a * l
    const distilledGrams = Math.max(l * 1000 - hardnessConcentrateGrams - calciumConcentrateGrams - bufferConcentrateGrams, 0.0)

    return {
      epsomGrams,
      calciumChlorideGrams,
      bakingSodaGrams,
      hardnessConcentrateGrams,
      calciumConcentrateGrams,
      bufferConcentrateGrams,
      distilledGrams,
    }
  },

  summary(hardness: number, alkalinity: number): string {
    return `GH ${Math.round(hardness)} · KH ${Math.round(alkalinity)} ppm`
  },

  character(hardness: number, alkalinity: number): string {
    if (hardness <= 0 && alkalinity <= 0) return 'Pure water: flat, sour coffee. Add minerals.'
    const parts: string[] = []
    if (alkalinity < 20) {
      parts.push('Low buffer: bright, more acidity.')
    } else if (alkalinity > 60) {
      parts.push('High buffer: mutes acidity, can taste chalky.')
    } else {
      parts.push('Moderate buffer: balanced acidity.')
    }

    if (hardness < 30) {
      parts.push('Soft: clean but less sweetness and body.')
    } else if (hardness > 120) {
      parts.push('Very hard: heavy, can over-extract and scales machines.')
    } else {
      parts.push('Hardness extracts sweetness well.')
    }
    return parts.join(' ')
  },
}
