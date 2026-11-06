import { roundHalfAway } from './format'
import { defaultStartingValue, formatGrind, grindSuffix, type GrinderSpec } from './models'

/**
 * Rough translation of grind settings between grinders. A calibrated grinder has a medium-fine filter setting
 * (GrinderSpec.defaultGrind) pinned at REFERENCE_MICRONS on a shared scale and GrinderSpec.micronsPerStep.
 * A starting point to taste from, not an exact match. Port of Tools/GrindConverter.swift / GrindConverter.kt.
 */
export const GrindConverter = {
  /** The shared scale's point for a medium-fine filter grind (Comandante 24 clicks). */
  REFERENCE_MICRONS: 720.0,

  /** Calibration of the grinder presets by name: µm per smallest step. */
  knownMicronsPerStep: {
    'Comandante C40': 30.0,
    '1Zpresso K-Ultra': 20.0,
    '1Zpresso ZP6 Special': 16.0,
    'Kingrinder K6': 16.0,
  } as Record<string, number>,

  /** The spec with the preset calibration filled in when the grinder has none of its own. */
  calibrated(spec: GrinderSpec, name: string): GrinderSpec {
    const presetMicrons = spec.micronsPerStep != null ? spec.micronsPerStep : spec.unit === 'microns' ? spec.step : GrindConverter.knownMicronsPerStep[name] ?? null
    const defaultGrind = spec.defaultGrind ?? defaultStartingValue(spec)
    return { ...spec, defaultGrind, micronsPerStep: presetMicrons }
  },

  canConvert(spec: GrinderSpec): boolean {
    return spec.defaultGrind != null && (spec.micronsPerStep ?? 0) > 0 && spec.step > 0
  },

  /** The setting's position on the shared µm scale. */
  microns(value: number, spec: GrinderSpec): number | null {
    if (!GrindConverter.canConvert(spec)) return null
    const steps = (value - spec.defaultGrind!) / spec.step
    return GrindConverter.REFERENCE_MICRONS + (spec.finerIsLower ? steps : -steps) * spec.micronsPerStep!
  },

  /** The setting on this grinder for a size on the shared scale, snapped to the grinder's steps. */
  value(microns: number, spec: GrinderSpec): number | null {
    if (!GrindConverter.canConvert(spec)) return null
    const steps = (microns - GrindConverter.REFERENCE_MICRONS) / spec.micronsPerStep!
    const raw = spec.defaultGrind! + (spec.finerIsLower ? steps : -steps) * spec.step
    return Math.max(0, roundHalfAway(raw / spec.step) * spec.step)
  },

  convert(value: number, from: GrinderSpec, to: GrinderSpec): number | null {
    const m = GrindConverter.microns(value, from)
    return m != null ? GrindConverter.value(m, to) : null
  },

  rangePattern: /(\d{3,4})\s*(?:[–—-]|to)\s*(\d{3,4})\s*(?:µm|μm|um|microns)|(\d{3,4})\s*(?:µm|μm|um|microns)/i,

  /** The grind size range in a recipe's grind text, e.g. "Medium-fine (about 600–750 µm)" → [600, 750]. */
  micronRange(text: string): [number, number] | null {
    const match = text.match(GrindConverter.rangePattern)
    if (!match) return null
    if (match[1] != null && match[2] != null) {
      const low = parseFloat(match[1])
      const high = parseFloat(match[2])
      if (!isNaN(low) && !isNaN(high)) return [Math.min(low, high), Math.max(low, high)]
    }
    if (match[3] != null) {
      const single = parseFloat(match[3])
      if (!isNaN(single)) return [single, single]
    }
    return null
  },

  /** The recipe's grind size on this grinder, e.g. "≈ 22–25 clicks". Null when the grinder isn't calibrated. */
  hint(recipeGrind: string, spec: GrinderSpec): string | null {
    const range = GrindConverter.micronRange(recipeGrind)
    if (!range) return null
    const a = GrindConverter.value(range[0], spec)
    const b = GrindConverter.value(range[1], spec)
    if (a == null || b == null) return null
    const low = Math.min(a, b)
    const high = Math.max(a, b)
    if (low === high) return `≈ ${formatGrind(spec, low)}`
    const suffix = grindSuffix(spec.unit)
    const lowFormatted = formatGrind(spec, low)
    const lowText = suffix ? lowFormatted.replace(new RegExp(`\\s*${suffix}$`), '') : lowFormatted
    return `≈ ${lowText}–${formatGrind(spec, high)}`
  },
}
