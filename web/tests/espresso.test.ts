import { describe, expect, it } from 'vitest'
import { analyze, type AnalysisInput } from '../src/analysis/analyzer'
import { pressureSummary } from '../src/analysis/espresso'
import { PRESET_RECIPES } from '../src/domain/library'
import type { GrinderSpec, MachineSample, TasteFeedback, WeightSample } from '../src/domain/models'
import { stepHeadline, type Recipe } from '../src/domain/recipe'
import { emptyStatus, gaggiMateUrl, hasWeight, isBrewing, isTelemetry, makeProfile, mergeStatus, statusFrame } from '../src/machine/gaggimate'
import { START_COMMAND, STOP_COMMAND, commandChecksum, isMonitorName, parsePressurePacket } from '../src/scale/pressure'

// Same scenarios and numbers as EspressoTests.swift.

const grinder: GrinderSpec = { unit: 'clicks', step: 1, adjustStep: 1, finerIsLower: true, rangeNote: '' }
const classic = (): Recipe => PRESET_RECIPES.find((r) => r.id === 'espresso-classic')!

function shot(drops: number, end: number, yieldGrams: number): WeightSample[] {
  const out: WeightSample[] = []
  for (let i = 0; i <= Math.round(end * 10); i++) {
    const t = i / 10
    out.push({ t, w: t < drops ? 0 : (yieldGrams * (t - drops)) / (end - drops) })
  }
  return out
}

function input(recipe: Recipe, time: number, yieldGrams: number, opts: { drops?: number; feedback?: TasteFeedback[]; machine?: MachineSample[] } = {}): AnalysisInput {
  return {
    recipe, samples: shot(opts.drops ?? 7, time, yieldGrams), usedScale: true, totalTime: time, finalWeight: yieldGrams, dose: recipe.dose,
    waterTemp: recipe.temperature, roastLevel: 'medium', daysOffRoast: 12, filterName: '', filterFlow: null, filterIdealRoast: null,
    grinder: { name: 'Niche', spec: grinder, currentValue: 12 }, feedback: opts.feedback ?? [], history: [], machine: opts.machine ?? [],
  }
}

describe('espresso recipes', () => {
  it('ships espresso presets with one extraction step', () => {
    const espresso = PRESET_RECIPES.filter((r) => r.method === 'espresso')
    expect(espresso.length).toBeGreaterThanOrEqual(3)
    for (const r of espresso) {
      const extract = r.steps.filter((s) => s.kind === 'extract')
      expect(extract).toHaveLength(1)
      expect(extract[0].target).toBe(r.water)
      expect(r.pressure).not.toBeNull()
    }
    expect(stepHeadline(classic().steps[classic().steps.length - 1])).toBe('Extract to 36 g')
  })
})

describe('espresso analysis', () => {
  it('on-time shot is balanced', () => {
    const a = analyze(input(classic(), 28, 36))
    expect(a.lean).toBe('balanced')
    expect(a.pours).toHaveLength(0)
    expect(a.findings.some((f) => f.title === 'Shot time 0:28')).toBe(true)
    expect(a.findings.some((f) => f.title === 'First drops at 0:07')).toBe(true)
    expect(a.suggestedGrind).toBeNull()
  })

  it('fast sour shot grinds finer', () => {
    const a = analyze(input(classic(), 19, 36, { drops: 4, feedback: ['sour'] }))
    expect(a.lean).toBe('under')
    expect(a.suggestions[0].key).toBe('grind')
    expect(a.suggestedGrind).toBe(10)
  })

  it('slow bitter shot grinds coarser', () => {
    const a = analyze(input(classic(), 34, 36, { feedback: ['bitter'] }))
    expect(a.lean).toBe('over')
    expect(a.suggestedGrind).toBe(13)
    expect(a.suggestions.some((s) => s.key === 'temp-down')).toBe(true)
  })

  it('sour at a good time runs longer, stopped-short is called out', () => {
    const a = analyze(input(classic(), 28, 36, { feedback: ['sour'] }))
    expect(a.suggestions[0].key).toBe('ratio')
    expect(a.suggestions[0].title).toContain('1:2.3')
    expect(a.suggestedGrind).toBeNull()
    expect(analyze(input(classic(), 27, 29, { feedback: ['sour'] })).suggestions[0].title).toBe('Let it run to 36 g')
  })

  it('a pressure drop means channeling, a steady decline is fine', () => {
    const drop: MachineSample[] = []
    const steady: MachineSample[] = []
    for (let t = 0; t <= 28; t += 0.5) {
      drop.push({ t, p: t < 6 ? 3 : t < 14 ? 9 : 6, c: 93, f: 2 })
      steady.push({ t, p: t < 6 ? 3 : 9 - (t - 6) * 0.1, c: 93, f: 2 })
    }
    const a = analyze(input(classic(), 28, 36, { machine: drop }))
    expect(a.lean).toBe('uneven')
    expect(a.suggestions[0].key).toBe('puck')
    expect(a.findings.some((f) => f.title.startsWith('Pressure fell 3.0 bar'))).toBe(true)
    expect(pressureSummary(drop)).toMatchObject({ peak: 9, averageTemperature: 93 })
    expect(pressureSummary(steady)!.suddenDrop).toBeLessThan(2)
    expect(analyze(input(classic(), 28, 36, { machine: steady })).lean).toBe('balanced')
  })

  it('perfect shot is the reference', () => {
    const a = analyze(input(classic(), 28, 36, { feedback: ['perfect'] }))
    expect(a.suggestions.map((s) => s.key)).toEqual(['repeat'])
    expect(a.suggestedGrind).toBe(12)
  })
})

describe('GaggiMate', () => {
  it('tracks the shot from status frames', () => {
    let status = mergeStatus(emptyStatus(), statusFrame('{"tp":"evt:status","m":1,"p":"9 Bar","cp":true,"bc":true,"sys":{"s":"ready","m":"","c":0}}')!)
    expect(status.mode).toBe(1)
    expect(status.systemState).toBe('ready')
    const brewing = statusFrame('{"tp":"evt:status","ct":92.6,"tt":93,"pr":8.94,"fl":2.1,"cw":12.4,"process":{"a":1,"s":"brew","l":"Extraction","e":9000}}')!
    expect(isTelemetry(brewing)).toBe(true)
    status = mergeStatus(status, brewing)
    expect(isBrewing(status)).toBe(true)
    expect(status.pressure).toBe(8.94)
    expect(hasWeight(status)).toBe(true)
    expect(status.profile).toBe('9 Bar')
    status = mergeStatus(status, statusFrame('{"tp":"evt:status","pr":0.2,"process":{"a":0,"s":"brew","l":"Finished"}}')!)
    expect(isBrewing(status)).toBe(false)
    status = mergeStatus(status, statusFrame('{"tp":"evt:status","pr":null,"process":null}')!)
    expect(status.pressure).toBeNull()
  })

  it('ignores flushes, grinds and other messages, clamps values', () => {
    expect(isBrewing(mergeStatus(emptyStatus(), statusFrame('{"tp":"evt:status","pr":9,"process":{"a":1,"s":"brew","u":1}}')!))).toBe(false)
    expect(isBrewing(mergeStatus(emptyStatus(), statusFrame('{"tp":"evt:status","process":{"a":1,"s":"grind"}}')!))).toBe(false)
    expect(statusFrame('{"tp":"res:profiles:list"}')).toBeNull()
    expect(statusFrame('not json')).toBeNull()
    const s = mergeStatus(emptyStatus(), statusFrame('{"tp":"evt:status","pr":250,"ct":-5}')!)
    expect(s.pressure).toBe(20)
    expect(s.temperature).toBe(0)
  })

  it('normalizes the address', () => {
    expect(gaggiMateUrl('gaggimate.local')).toBe('ws://gaggimate.local/ws')
    expect(gaggiMateUrl(' http://GaggiMate.local/ ')).toBe('ws://gaggimate.local/ws')
    expect(gaggiMateUrl('ws://10.0.0.5/ws')).toBe('ws://10.0.0.5/ws')
    expect(gaggiMateUrl('')).toBeNull()
    expect(gaggiMateUrl('evil.com/ws?x=1')).toBeNull()
  })

  it('builds profiles like iOS', () => {
    const p = makeProfile(classic(), 18, 93, true, true) as { label: string; type: string; phases: Record<string, unknown>[] }
    expect(p.label).toBe('BrewLog · Classic Espresso 1:2')
    expect(p.type).toBe('pro')
    expect(p.phases.map((x) => x.phase)).toEqual(['preinfusion', 'brew'])
    expect(p.phases[0].duration).toBe(5)
    expect(p.phases[1].duration).toBe(48)
    expect((p.phases[1].targets as { value: number }[])[0].value).toBe(36)
    const plain = makeProfile(classic(), 20, 94, false, false) as { dose: number; description: string; phases: Record<string, unknown>[] }
    expect(plain.phases).toHaveLength(1)
    expect(plain.phases[0].pump).toBe(100)
    expect(plain.phases[0].duration).toBe(28)
    expect(plain.description).toContain('40 g out')
  })
})

describe('BOOKOO Espresso Monitor', () => {
  it('parses pressure packets (same bytes as iOS and Android)', () => {
    expect(parsePressurePacket([0x02, 0x1b, 0x00, 0x00, 0x03, 0x84, 0x50, 0x00, 0x00, 0x00])).toEqual({ bar: 9, batteryPercent: 80 })
    expect(parsePressurePacket([0x03, 0x0b, 0, 0, 0x03, 0x84, 0x50, 0, 0, 0])).toBeNull()
    expect(parsePressurePacket([0x02, 0x1b, 0, 0, 0xff, 0xff, 0x50, 0, 0, 0])).toBeNull()
    expect(parsePressurePacket([0x02, 0x1b, 0, 0])).toBeNull()
  })

  it('commands carry the XOR checksum and names exclude the scale', () => {
    expect(commandChecksum(START_COMMAND)).toBe(START_COMMAND[6])
    expect(commandChecksum(STOP_COMMAND)).toBe(STOP_COMMAND[6])
    expect(isMonitorName('BOOKOO_EM 0A12')).toBe(true)
    expect(isMonitorName('BOOKOO_SC 77F1')).toBe(false)
  })
})
