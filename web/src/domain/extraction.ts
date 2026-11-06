export type ExtractionVerdict = 'under' | 'ideal' | 'over'
export type ExtractionStrength = 'weak' | 'ideal' | 'strong'

export interface ExtractionReading {
  tds: number
  yield: number
  verdict: ExtractionVerdict
  strength: ExtractionStrength
  advice: string
}

export const VERDICT_TITLES: Record<ExtractionVerdict, string> = {
  under: 'Under-extracted',
  ideal: 'In the ideal range',
  over: 'Over-extracted',
}

export const STRENGTH_TITLES: Record<ExtractionStrength, string> = {
  weak: 'weak',
  ideal: 'ideal strength',
  strong: 'strong',
}

/**
 * Extraction yield from a refractometer reading (TDS): EY % = beverage (g) × TDS % / dose (g).
 * The beverage is what ends up in the cup, not the water poured: the grounds hold back about twice their dry weight.
 * Port of Tools/Extraction.swift / Extraction.kt.
 */
export const Extraction = {
  /** Water the spent grounds hold back, in grams per gram of coffee (pour-over). */
  RETENTION_RATIO: 2.0,
  MAX_TDS: 25.0,

  /** Extraction yield in percent, null when an input is missing. */
  yield(tds: number, beverage: number, dose: number): number | null {
    return tds > 0 && beverage > 0 && dose > 0 ? (beverage * tds) / dose : null
  },

  /** Estimated drink weight when it wasn't weighed: the yield for espresso, the poured water minus what the grounds absorb for filter. */
  estimatedBeverage(finalWeight: number, dose: number, espresso: boolean): number {
    if (finalWeight <= 0) return 0.0
    if (espresso) return finalWeight
    return Math.max(finalWeight - dose * Extraction.RETENTION_RATIO, 0.0)
  },

  /** The classic brewing control chart zones (SCA / Gold Cup for filter, common espresso targets). */
  zone(espresso: boolean): { tdsMin: number; tdsMax: number; eyMin: number; eyMax: number } {
    return espresso
      ? { tdsMin: 8.0, tdsMax: 12.0, eyMin: 18.0, eyMax: 22.0 }
      : { tdsMin: 1.15, tdsMax: 1.45, eyMin: 18.0, eyMax: 22.0 }
  },

  evaluate(tds: number, beverage: number, dose: number, espresso: boolean): ExtractionReading | null {
    const ey = Extraction.yield(tds, beverage, dose)
    if (ey == null) return null
    const z = Extraction.zone(espresso)

    const verdict: ExtractionVerdict = ey < z.eyMin ? 'under' : ey > z.eyMax ? 'over' : 'ideal'
    const strength: ExtractionStrength = tds < z.tdsMin ? 'weak' : tds > z.tdsMax ? 'strong' : 'ideal'

    const parts: string[] = []
    if (verdict === 'under') {
      parts.push('Extract more: grind finer, use hotter water or brew longer.')
    } else if (verdict === 'over') {
      parts.push('Extract less: grind coarser, use cooler water or brew shorter.')
    }

    if (strength === 'weak') {
      parts.push('For a stronger cup use more coffee for the same water (lower ratio).')
    } else if (strength === 'strong') {
      parts.push('For a lighter cup use more water for the same coffee (higher ratio).')
    }

    const advice = parts.length > 0 ? parts.join(' ') : 'Balanced on both strength and extraction.'
    return { tds, yield: ey, verdict, strength, advice }
  },
}
