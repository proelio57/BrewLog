import { describe, expect, it } from 'vitest'
import { Extraction } from '../src/domain/extraction'
import { WaterChemistry } from '../src/domain/waterChemistry'
import { GrindConverter } from '../src/domain/grindConverter'
import type { GrinderSpec } from '../src/domain/models'

describe('Tools - Extraction (TDS / EY)', () => {
  it('calculates extraction yield', () => {
    // 15 g coffee, 220 g in the cup at 1.35 % TDS → 19.8 %
    expect(Extraction.yield(1.35, 220.0, 15.0)).toBeCloseTo(19.8, 3)
    expect(Extraction.yield(0.0, 220.0, 15.0)).toBeNull()
    expect(Extraction.yield(1.3, 220.0, 0.0)).toBeNull()
  })

  it('estimates beverage weight when unweighed', () => {
    expect(Extraction.estimatedBeverage(250.0, 15.0, false)).toBe(220.0)
    expect(Extraction.estimatedBeverage(36.0, 18.0, true)).toBe(36.0)
    expect(Extraction.estimatedBeverage(10.0, 15.0, false)).toBe(0.0)
  })

  it('evaluates extraction and strength verdicts with advice', () => {
    const ideal = Extraction.evaluate(1.35, 220.0, 15.0, false)!
    expect(ideal.verdict).toBe('ideal')
    expect(ideal.strength).toBe('ideal')

    const under = Extraction.evaluate(1.1, 220.0, 15.0, false)!
    expect(under.verdict).toBe('under')
    expect(under.strength).toBe('weak')
    expect(under.advice).toContain('grind finer')

    const espresso = Extraction.evaluate(10.0, 36.0, 18.0, true)!
    expect(espresso.yield).toBeCloseTo(20.0, 3)
    expect(espresso.verdict).toBe('ideal')

    const over = Extraction.evaluate(12.5, 36.0, 18.0, true)!
    expect(over.verdict).toBe('over')
    expect(over.strength).toBe('strong')
  })
})

describe('Tools - Water Chemistry', () => {
  it('water minerals match Barista Hustle concentrates', () => {
    expect(WaterChemistry.EPSOM_PER_PPM).toBeCloseTo(2.46, 2)
    expect(WaterChemistry.BAKING_SODA_PER_PPM).toBeCloseTo(1.68, 2)
    expect(WaterChemistry.CALCIUM_CHLORIDE_PER_PPM).toBeCloseTo(1.47, 2)
  })

  it('calculates water recipes for salts and concentrates', () => {
    const sca = WaterChemistry.calculate(68.0, 40.0, 4.0)
    expect(sca.epsomGrams).toBeCloseTo((68 * (246.47 / 100.09) * 4) / 1000, 3)
    expect(sca.calciumChlorideGrams).toBe(0.0)
    expect(sca.bakingSodaGrams).toBeCloseTo((40 * ((2 * 84.007) / 100.09) * 4) / 1000, 3)
    expect(sca.hardnessConcentrateGrams).toBe(272.0)
    expect(sca.bufferConcentrateGrams).toBe(160.0)
    expect(sca.distilledGrams).toBe(4000.0 - 272 - 160)

    const mixed = WaterChemistry.calculate(100.0, 0.0, 1.0, 0.5)
    expect(mixed.epsomGrams).toBeCloseTo((50 * WaterChemistry.EPSOM_PER_PPM) / 1000, 4)
    expect(mixed.calciumChlorideGrams).toBeCloseTo((50 * WaterChemistry.CALCIUM_CHLORIDE_PER_PPM) / 1000, 4)
    expect(mixed.hardnessConcentrateGrams + mixed.calciumConcentrateGrams).toBe(100.0)
  })

  it('clamps water inputs safely', () => {
    const silly = WaterChemistry.calculate(99999.0, -5.0, 1000.0, 3.0)
    expect(silly.hardnessConcentrateGrams).toBe(WaterChemistry.MAX_PPM * WaterChemistry.MAX_LITRES)
    expect(silly.bakingSodaGrams).toBe(0.0)
    expect(silly.calciumChlorideGrams).toBe(0.0)
    expect(silly.distilledGrams).toBeGreaterThanOrEqual(0)
  })

  it('checks presets and character notes', () => {
    const names = WaterChemistry.presets.map((p) => p.name)
    expect(new Set(names).size).toBe(names.length)
    expect(WaterChemistry.summary(68.0, 40.0)).toBe('GH 68 · KH 40 ppm')
    expect(WaterChemistry.character(0.0, 0.0)).toContain('Add minerals')
    expect(WaterChemistry.character(100.0, 10.0)).toContain('bright')
  })
})

describe('Tools - Grind Converter', () => {
  const comandante: GrinderSpec = {
    unit: 'clicks',
    step: 1.0,
    adjustStep: 2.0,
    finerIsLower: true,
    rangeNote: '20–30 clicks',
    defaultGrind: 24.0,
    micronsPerStep: 30.0,
  }

  const kUltra: GrinderSpec = {
    unit: 'numbers',
    step: 0.1,
    adjustStep: 0.2,
    finerIsLower: true,
    rangeNote: '7.0–8.5',
    defaultGrind: 7.5,
    micronsPerStep: 20.0,
  }

  it('converts between calibrated grinders', () => {
    expect(GrindConverter.convert(24.0, comandante, kUltra)).toBeCloseTo(7.5, 4)
    // 2 clicks finer = 60 µm = 3 steps of 0.1 on the K-Ultra
    expect(GrindConverter.convert(22.0, comandante, kUltra)).toBeCloseTo(7.2, 4)
    expect(GrindConverter.convert(7.8, kUltra, comandante)).toBeCloseTo(26.0, 4)
    expect(GrindConverter.microns(24.0, comandante)).toBe(720.0)
  })

  it('requires calibration to convert', () => {
    const unknown: GrinderSpec = {
      unit: 'dial',
      step: 1.0,
      adjustStep: 1.0,
      finerIsLower: true,
      rangeNote: '',
      defaultGrind: 5.0,
    }
    expect(GrindConverter.canConvert(unknown)).toBe(false)
    expect(GrindConverter.convert(5.0, unknown, comandante)).toBeNull()
    expect(GrindConverter.calibrated({ ...unknown, defaultGrind: 24.0 }, 'Comandante C40').micronsPerStep).toBe(30.0)
    expect(GrindConverter.calibrated({ ...unknown, micronsPerStep: 25.0 }, 'Comandante C40').micronsPerStep).toBe(25.0)
  })

  it('handles grinders where finer is higher', () => {
    expect(GrindConverter.convert(22.0, comandante, { ...comandante, finerIsLower: false })).toBeCloseTo(26.0, 4)
  })

  it('extracts micron ranges and produces grinder hints', () => {
    expect(GrindConverter.micronRange('Medium-fine (roughly 600–750 µm, e.g. Comandante 22–25 clicks)')).toEqual([
      600.0, 750.0,
    ])
    expect(GrindConverter.micronRange('Medium (approx. 750 µm)')).toEqual([750.0, 750.0])
    expect(GrindConverter.micronRange('Fine (espresso). Adjust so the shot takes 25–30 s.')).toBeNull()
    expect(GrindConverter.hint('about 600–750 µm', comandante)).toBe('≈ 20–25 clicks')
    expect(GrindConverter.hint('approx. 720 µm', kUltra)).toBe('≈ 7.5')
  })
})
