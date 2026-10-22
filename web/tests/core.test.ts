import { afterEach, describe, expect, it, vi } from 'vitest'
import { analyze, bracketed, centeredFlows, detectSegments, matchPours, startDelta, type AnalysisInput, type GrinderContext, type PastBrew } from '../src/analysis/analyzer'
import { recommendGrind } from '../src/analysis/recommender'
import { BrewSession, slope, type BrewCue } from '../src/brewing/brewSession'
import { BrewSetup } from '../src/data/setup'
import { mmss, newId } from '../src/domain/format'
import { PRESET_RECIPES, blankRecipe } from '../src/domain/library'
import {
  DEFAULT_SETTINGS, adjustGrind, defaultGrinderSpec, formatGrind, formatGrindDelta, grindDisplay, newBean, type Brew, type Equipment, type GrinderSpec,
  type RoastLevel, type TasteFeedback, type WeightSample,
} from '../src/domain/models'
import { pourSteps, scaled, targetCurve, type Recipe } from '../src/domain/recipe'
import { LIMITS, clamped, parseAppData, parseRecipe, parseSamples, sanitized, validatedRecipe } from '../src/domain/validation'
import { PacketValidator, checksum, commandPacket, parseReading } from '../src/scale/bookoo'
import type { ScaleCommands } from '../src/scale/scaleManager'
import recipesJson from '../../Shared/recipes.json'

// Same scenarios and numbers as the iOS (XCTest) and Android (JUnit) tests, so all platforms agree.

afterEach(() => {
  vi.unstubAllGlobals()
})

/** In-memory Web Storage for the setup tests (Node has no persistent localStorage by default). */
function memoryStorage(): Storage {
  const map = new Map<string, string>()
  return {
    get length() { return map.size },
    clear: () => map.clear(),
    getItem: (key) => map.get(key) ?? null,
    key: (index) => [...map.keys()][index] ?? null,
    removeItem: (key) => { map.delete(key) },
    setItem: (key, value) => { map.set(key, String(value)) },
  }
}

/** Builds a weight packet as documented by BOOKOO. */
function packet(grams: number, { negative = false, flow = 0, battery = 87, validChecksum = true, header = 0x0b } = {}): Uint8Array {
  const raw = Math.round(Math.abs(grams) * 100)
  const flowRaw = Math.round(Math.abs(flow) * 100)
  const b = [0x03, header, 0x00, 0x10, 0x20, 0x01, negative ? 0x2d : 0x2b, (raw >> 16) & 0xff, (raw >> 8) & 0xff, raw & 0xff,
    flow < 0 ? 0x2d : 0x2b, (flowRaw >> 8) & 0xff, flowRaw & 0xff, battery, 0x00, 0x32, 0x03, 0x01, 0x00]
  const sum = b.reduce((a, v) => a ^ v, 0)
  return Uint8Array.from([...b, validChecksum ? sum : sum ^ 0xff])
}

describe('BOOKOO protocol', () => {
  it('parses weight, flow and battery', () => {
    const r = parseReading(packet(123.45, { flow: 4.5 }))!
    expect(r.grams).toBeCloseTo(123.45, 3)
    expect(r.flowRate).toBeCloseTo(4.5, 3)
    expect(r.batteryPercent).toBe(87)
    expect(r.milliseconds).toBe(0x001020)
    expect(r.checksumValid).toBe(true)
    expect(parseReading(packet(2.3, { negative: true }))!.grams).toBeCloseTo(-2.3, 3)
  })

  it('rejects malformed packets', () => {
    expect(parseReading(new Uint8Array(0))).toBeNull()
    expect(parseReading(new Uint8Array(19).fill(3))).toBeNull()
    expect(parseReading(new Uint8Array(200).fill(3))).toBeNull()
    expect(parseReading(packet(10, { header: 0x0a }))).toBeNull()
    expect(parseReading(packet(90_000))).toBeNull()
    expect(parseReading(packet(1, { battery: 250 }))!.batteryPercent).toBe(100)
    expect(parseReading(packet(5, { validChecksum: false }))!.checksumValid).toBe(false)
  })

  it('only sends the four allowlisted, field-tested commands', () => {
    expect([...commandPacket('tare')]).toEqual([0x03, 0x0a, 0x01, 0x00, 0x00, 0x08])
    expect([...commandPacket('startTimer')]).toEqual([0x03, 0x0a, 0x04, 0x00, 0x00, 0x0a])
    expect([...commandPacket('stopTimer')]).toEqual([0x03, 0x0a, 0x05, 0x00, 0x00, 0x0d])
    expect([...commandPacket('resetTimer')]).toEqual([0x03, 0x0a, 0x06, 0x00, 0x00, 0x0c])
    expect(checksum([0x03, 0x0a, 0x01, 0x00, 0x00])).toBe(0x08)
    const copy = commandPacket('tare')
    copy[5] = 0
    expect(commandPacket('tare')[5]).toBe(0x08)
  })

  it('enforces checksums only when the firmware follows the spec', () => {
    const strict = new PacketValidator()
    for (let i = 0; i < 10; i++) expect(strict.accept(packet(1))).not.toBeNull()
    expect(strict.policy).toBe('enforced')
    expect(strict.accept(packet(1, { validChecksum: false }))).toBeNull()
    const lenient = new PacketValidator()
    for (let i = 0; i < 10; i++) lenient.accept(packet(1, { validChecksum: false }))
    expect(lenient.policy).toBe('ignored')
    expect(lenient.accept(packet(3, { validChecksum: false }))).not.toBeNull()
    expect(lenient.accept(new Uint8Array(20))).toBeNull()
  })
})

describe('recipes & validation', () => {
  it('loads consistent presets', () => {
    expect(PRESET_RECIPES.length).toBeGreaterThanOrEqual(9)
    expect(new Set(PRESET_RECIPES.map((r) => r.id)).size).toBe(PRESET_RECIPES.length)
    for (const r of PRESET_RECIPES) {
      expect(r.tasteNotes.length).toBeGreaterThan(0)
      expect(r.steps[0].time).toBe(0)
      const times = r.steps.map((s) => s.time)
      expect(times).toEqual([...times].sort((a, b) => a - b))
      const targets = pourSteps(r).map((s) => s.target!)
      expect(targets).toEqual([...targets].sort((a, b) => a - b))
      expect(targets[targets.length - 1]).toBeCloseTo(r.water, 0)
      expect(r.targetTime).toBeGreaterThanOrEqual(times[times.length - 1])
    }
  })

  it('loads every recipe of the shared iOS/Android file', () => {
    expect(PRESET_RECIPES.map((r) => r.id)).toEqual((recipesJson as Recipe[]).map((r) => r.id))
  })

  it('bundled JSON is already valid', () => {
    for (const raw of recipesJson as Recipe[]) {
      const parsed = parseRecipe(raw)!
      expect(parsed.steps.map((s) => [s.kind, s.time, s.target ?? null])).toEqual(raw.steps.map((s) => [s.kind, s.time, s.target ?? null]))
      expect(parsed.targetTime).toBe(raw.targetTime)
      expect(parsed.water).toBe(raw.water)
    }
  })

  it('scales weights and keeps times', () => {
    const r = PRESET_RECIPES.find((x) => x.id === 'kasuya-46')!
    const s = scaled(r, 30)
    expect(s.water).toBe(450)
    expect(s.steps.map((x) => x.time)).toEqual(r.steps.map((x) => x.time))
    expect(pourSteps(s).map((x) => x.target)).toEqual([90, 180, 270, 360, 450])
    const curve = targetCurve(PRESET_RECIPES.find((x) => x.id === 'hoffmann-ultimate-v60')!)
    expect(curve[curve.length - 1]).toEqual([210, 500])
  })

  it('clamps hostile values', () => {
    const clean = validatedRecipe({
      ...blankRecipe(),
      name: '  \u0000Evil\u0007 name ' + 'x'.repeat(500), dose: NaN, water: -50, temperature: 1000, targetTime: Infinity,
      flowMin: 10, flowMax: 2, taste: { acidity: 99, sweetness: -3, body: 3, clarity: 0 },
      steps: [
        { kind: 'pour', time: 60, target: 50 },
        { kind: 'bloom', time: -5, target: 1_000_000 },
        { kind: 'swirl', time: 9999, target: 42, note: 'n'.repeat(999) },
        ...Array.from({ length: 100 }, () => ({ kind: 'pour' as const, time: 10, target: 1 })),
      ],
    })
    expect(clean.name.startsWith('Evil name')).toBe(true)
    expect(clean.name.length).toBeLessThanOrEqual(LIMITS.maxNameLength)
    expect(clean.dose).toBe(1)
    expect(clean.water).toBe(10)
    expect(clean.temperature).toBe(100)
    expect(Number.isFinite(clean.targetTime)).toBe(true)
    expect(clean.flowMax).toBeGreaterThan(clean.flowMin)
    expect(clean.taste).toEqual({ acidity: 5, sweetness: 1, body: 3, clarity: 1 })
    expect(clean.steps.length).toBeLessThanOrEqual(LIMITS.maxSteps)
    const targets = pourSteps(clean).map((s) => s.target!)
    expect(targets).toEqual([...targets].sort((a, b) => a - b))
    expect(clean.steps.find((s) => s.kind === 'swirl')!.target).toBeNull()
  })

  it('sanitizes strings and numbers', () => {
    expect(sanitized('  hello\u0000\u001Bworld  ', 50)).toBe('helloworld')
    expect(sanitized('abcdef', 3)).toBe('abc')
    expect(sanitized('line1\nline2', 50)).toBe('line1\nline2')
    expect(clamped(NaN, 1, 5)).toBe(1)
    expect(clamped(7, 1, 5)).toBe(5)
    expect(newId()).toMatch(/^[A-Za-z0-9_-]{1,120}$/)
    vi.stubGlobal('crypto', { getRandomValues: (a: Uint8Array) => a.fill(171) }) // plain http: no randomUUID
    expect(newId()).toMatch(/^id-[a-z0-9]+-(ab){12}$/)
    vi.stubGlobal('crypto', undefined)
    expect(newId()).toMatch(/^id-[a-z0-9]+-[a-z0-9]+$/)
    vi.unstubAllGlobals()
    expect(mmss(0)).toBe('0:00')
    expect(mmss(65.9)).toBe('1:05')
    expect(mmss(210)).toBe('3:30')
  })

  it('parses untrusted backup data safely', () => {
    const data = parseAppData({
      beans: [{ id: '../../evil', name: 'Guji<script>', roastLevel: 'nuclear', bagWeight: 1e12 }, { name: '' }, 'garbage'],
      equipment: [{ name: 'Grinder', type: 'grinder', grinder: { step: -5, adjustStep: NaN } }],
      brews: [{ id: 'b1', rating: 99, feedback: ['sour', 'hacked', 'sour'], recipe: { steps: 'nope' } }],
      customRecipes: [{ id: 'x', name: 'Mine', steps: [{ kind: 'pour', time: 0, target: 100 }] }],
    })
    expect(data.beans).toHaveLength(1)
    expect(data.beans[0].id).not.toContain('/')
    expect(data.beans[0].roastLevel).toBe('light')
    expect(data.beans[0].bagWeight).toBe(LIMITS.maxBagWeight)
    expect(data.equipment[0].grinder.step).toBe(0.01)
    expect(data.brews[0].rating).toBe(5)
    expect(data.brews[0].feedback).toEqual(['sour'])
    expect(data.brews[0].recipe).toBeNull()
    expect(data.customRecipes[0].isCustom).toBe(true)
    expect(parseSamples([[1, 2], { t: 3, w: 4 }, [NaN, 1], 'x'])).toEqual([{ t: 1, w: 2 }, { t: 3, w: 4 }])
  })
})

describe('grinder scale', () => {
  const comandante: GrinderSpec = { unit: 'clicks', step: 1, adjustStep: 2, finerIsLower: true, rangeNote: '' }
  it('adjusts and formats', () => {
    expect(adjustGrind(comandante, 24, false)).toBe(22)
    expect(adjustGrind(comandante, 24, true)).toBe(26)
    expect(adjustGrind(comandante, 24, false, 2)).toBe(20)
    expect(adjustGrind(comandante, 1, false)).toBe(0)
    expect(adjustGrind({ ...comandante, unit: 'numbers', adjustStep: 1, finerIsLower: false }, 10, false)).toBe(11)
    expect(adjustGrind({ unit: 'dial', step: 0.1, adjustStep: 0.2, finerIsLower: true, rangeNote: '' }, 7.5, false)).toBeCloseTo(7.3, 4)
    expect(formatGrind(comandante, 24)).toBe('24 clicks')
    expect(formatGrindDelta(comandante, 1)).toBe('1 click')
    expect(formatGrindDelta(comandante, -2)).toBe('2 clicks')
    expect(formatGrind({ ...defaultGrinderSpec(), unit: 'dial', step: 0.1 }, 7.5)).toBe('7.5')
  })
})

describe('analyzer', () => {
  const comandante: GrinderSpec = { unit: 'clicks', step: 1, adjustStep: 2, finerIsLower: true, rangeNote: '' }
  const kasuya = () => PRESET_RECIPES.find((r) => r.id === 'kasuya-46')!
  const fastCase = () => ({ ...kasuya(), targetTime: 230 })
  const grinder = (value: number): GrinderContext => ({ name: 'Comandante C40', spec: comandante, currentValue: value })

  /** Each pour starts at its scheduled time (+ delay) and rises at `rate` g/s up to its target (+ overshoot). 10 Hz. */
  function simulate(recipe: Recipe, until: number, { rate = 6, delays = [] as number[], overshoot = [] as number[] } = {}): WeightSample[] {
    const pours = pourSteps(recipe)
    const samples: WeightSample[] = []
    let weight = 0
    for (let i = 0; i / 10 <= until + 0.0001; i++) {
      const t = i / 10
      let index = -1
      pours.forEach((p, k) => { if (p.time + (delays[k] ?? 0) <= t) index = k })
      if (index >= 0) {
        const goal = (pours[index].target ?? 0) + (overshoot[index] ?? 0)
        if (weight < goal) weight = Math.min(goal, weight + rate * 0.1)
      }
      samples.push({ t, w: weight })
    }
    return samples
  }

  function input(recipe: Recipe, samples: WeightSample[], totalTime: number, opts: {
    finalWeight?: number; temp?: number; roast?: RoastLevel | null; days?: number | null; grinder?: GrinderContext | null
    feedback?: TasteFeedback[]; history?: PastBrew[]; filterIdealRoast?: RoastLevel | null; usedScale?: boolean
  } = {}): AnalysisInput {
    return {
      recipe, samples, usedScale: opts.usedScale ?? true, totalTime,
      finalWeight: opts.finalWeight ?? Math.max(0, ...samples.map((s) => s.w)), dose: recipe.dose,
      waterTemp: opts.temp ?? recipe.temperature, roastLevel: opts.roast === undefined ? 'light' : opts.roast,
      daysOffRoast: opts.days === undefined ? 14 : opts.days, filterName: 'Test paper', filterFlow: 'medium',
      filterIdealRoast: opts.filterIdealRoast ?? null, grinder: opts.grinder ?? null, feedback: opts.feedback ?? [], history: opts.history ?? [],
    }
  }

  it('detects every pour of 4:6', () => {
    const recipe = kasuya()
    const segments = detectSegments(simulate(recipe, 210))
    expect(segments).toHaveLength(5)
    segments.forEach((s, i) => {
      expect(Math.abs(s.start - pourSteps(recipe)[i].time)).toBeLessThanOrEqual(0.3)
      expect(s.endWeight).toBeCloseTo(pourSteps(recipe)[i].target!, 0)
    })
    const pours = matchPours(recipe, segments)
    expect(pours.map((p) => p.number)).toEqual([0, 1, 2, 3, 4])
    expect(pours[2].averageFlow!).toBeCloseTo(6, 0)
  })

  it('flags a late start and an overpour', () => {
    const recipe = kasuya()
    const samples = simulate(recipe, 215, { delays: [0, 9, 0, 0, 0], overshoot: [0, 12, 12, 12, 12] })
    const a = analyze(input(recipe, samples, 215, { finalWeight: 312 }))
    expect(startDelta(a.pours[1])!).toBeCloseTo(9, 0)
    expect(a.findings.some((f) => f.title.includes('Pour 1 started 9 s late'))).toBe(true)
    expect(a.findings.some((f) => f.title.includes('overpoured by 12 g'))).toBe(true)
  })

  it('splits a continuous pour at an intermediate target', () => {
    const recipe = PRESET_RECIPES.find((r) => r.id === 'hoffmann-ultimate-v60')!
    const samples = Array.from({ length: 2101 }, (_, i) => {
      const t = i / 10
      return { t, w: t < 10 ? t * 6 : t < 45 ? 60 : Math.min(60 + (t - 45) * 8, 500) }
    })
    const a = analyze(input(recipe, samples, 210))
    expect(a.pours).toHaveLength(3)
    expect(a.pours.every((p) => p.actualStart != null)).toBe(true)
    expect(Math.abs(a.pours[1].reached! - 300)).toBeLessThanOrEqual(9)
    expect(Math.abs(a.pours[2].actualStart! - 75)).toBeLessThanOrEqual(1.5)
  })

  it('on-plan brew is balanced', () => {
    const a = analyze(input(kasuya(), simulate(kasuya(), 210), 210))
    expect(a.lean).toBe('balanced')
    expect(a.findings.some((f) => f.level === 'warning')).toBe(false)
  })

  it('sour + fast → concrete finer grind', () => {
    const a = analyze(input(fastCase(), simulate(fastCase(), 205), 205, { grinder: grinder(24), feedback: ['sour'] }))
    expect(a.suggestions[0].key).toBe('grind')
    expect(a.suggestions[0].grindTarget).toBe(22)
    expect(a.suggestions[0].title).toContain('22 clicks')
    expect(a.suggestions[0].evidence.length).toBeGreaterThan(0)
    expect(a.suggestedGrind).toBe(22)
    expect(a.lean).toBe('under')
  })

  it('very fast brew → two steps finer', () => {
    const recipe = { ...kasuya(), targetTime: 270 }
    expect(analyze(input(recipe, simulate(recipe, 200), 200, { grinder: grinder(24), feedback: ['sour'] })).suggestedGrind).toBe(20)
  })

  it('bitter + slow → coarser', () => {
    const a = analyze(input(kasuya(), simulate(kasuya(), 240), 240, { grinder: grinder(24), feedback: ['bitter'] }))
    expect(a.suggestions[0].key).toBe('grind')
    expect(a.suggestedGrind).toBe(26)
    expect(a.lean).toBe('over')
  })

  it('history brackets the grind', () => {
    const history: PastBrew[] = [{ date: 0, recipeId: 'kasuya-46', grindValue: 18, rating: 2, feedback: ['bitter'], totalTime: 240 }]
    const a = analyze(input(fastCase(), simulate(fastCase(), 205), 205, { grinder: grinder(24), feedback: ['sour'], history }))
    expect(a.suggestedGrind).toBe(21)
    expect(bracketed(false, 24, grinder(24), history)).toBe(21)
  })

  it('sour + bitter → uneven extraction', () => {
    const a = analyze(input(kasuya(), simulate(kasuya(), 210), 210, { feedback: ['sour', 'bitter'] }))
    expect(a.lean).toBe('uneven')
    expect(a.suggestions[0].key).toBe('evenness')
  })

  it('perfect keeps settings', () => {
    const a = analyze(input(kasuya(), simulate(kasuya(), 210), 210, { grinder: grinder(23), feedback: ['perfect'] }))
    expect(a.suggestions.map((s) => s.key)).toEqual(['repeat'])
    expect(a.suggestedGrind).toBe(23)
  })

  it('more rules: temperature, grinder nudge, paper, ratio, 4:6, manual, missing drawdown', () => {
    const cold = analyze(input(kasuya(), simulate(kasuya(), 210), 210, { temp: 86, feedback: ['sour'] }))
    expect(cold.suggestions.some((s) => s.key === 'temp-up' && s.evidence.length > 0)).toBe(true)
    expect(cold.findings.some((f) => f.title.includes('Cool water'))).toBe(true)
    expect(cold.suggestions.some((s) => s.key === '46-sweet')).toBe(true)

    const noGrinder = analyze(input(fastCase(), simulate(fastCase(), 205), 205, { feedback: ['sour'] }))
    expect(noGrinder.suggestions.find((s) => s.key === 'grind')!.grindTarget).toBeNull()
    expect(noGrinder.findings.some((f) => f.title === 'No grinder selected')).toBe(true)

    expect(analyze(input(kasuya(), simulate(kasuya(), 210), 210, { filterIdealRoast: 'dark' })).findings.some((f) => f.title.includes('Dark-roast paper'))).toBe(true)

    const weak = analyze(input(kasuya(), simulate(kasuya(), 215, { overshoot: [0, 0, 0, 0, 30] }), 215, { finalWeight: 330, feedback: ['weak'] }))
    expect(weak.suggestions[0].key).toBe('ratio-strength')

    const manual = analyze(input(kasuya(), [], 260, { finalWeight: 300, feedback: ['bitter'], usedScale: false }))
    expect(manual.pours).toHaveLength(0)
    expect(manual.suggestions[0].key).toBe('grind')

    const missing = analyze(input(kasuya(), simulate(kasuya(), 192), 192, { grinder: grinder(24), feedback: ['sour'] }))
    expect(missing.findings.some((f) => f.title === 'Drawdown not recorded')).toBe(true)
    expect(missing.findings.some((f) => f.title.includes('finished fast'))).toBe(false)
    expect(missing.suggestions.find((s) => s.key === 'grind')!.evidence).toEqual([])
  })

  it('centred flow follows the pour', () => {
    const samples = Array.from({ length: 151 }, (_, i) => ({ t: i / 10, w: Math.min(i / 10, 10) * 6 }))
    const flows = centeredFlows(samples)
    expect(flows[50]).toBeCloseTo(6, 2)
    expect(flows[140]).toBeCloseTo(0, 2)
    expect(flows[100]).toBeGreaterThan(1)
    expect(flows[100]).toBeLessThan(5)
    expect(centeredFlows([])).toEqual([])
  })
})

describe('grind recommender', () => {
  const grinderItem: Equipment = {
    id: 'g1', name: 'Comandante C40', type: 'grinder', notes: '', method: null, filterFlow: null, idealRoast: null,
    grinder: { unit: 'clicks', step: 1, adjustStep: 2, finerIsLower: true, rangeNote: '' }, createdAt: 0,
  }
  const brew = (beanId: string | null, grind: number, daysAgo: number, extra: Partial<Brew> = {}): Brew => ({
    id: `b${Math.random().toString(36).slice(2)}`, date: Date.now() - daysAgo * 86_400_000, recipeId: 'kasuya-46', recipeName: '4:6', recipe: null,
    dose: 20, targetWater: 300, finalWeight: 300, totalTime: 210, waterTemp: 92, grindSetting: '', grindValue: grind, suggestedGrind: null,
    brewerId: null, brewerName: '', grinderId: 'g1', grinderName: 'Comandante C40', grinderSpec: grinderItem.grinder, filterId: null, filterName: '',
    filterFlow: null, filterIdealRoast: null, beanId, usedScale: true, rating: 0, feedback: [], notes: '', externalId: null, ...extra,
  })

  it('works through its preference order', () => {
    expect(recommendGrind(null, grinderItem, 'kasuya-46', [])).toBeNull()
    expect(recommendGrind(null, null, 'kasuya-46', [])).toBeNull()
    const suggested = recommendGrind('bean', grinderItem, 'kasuya-46', [
      brew('bean', 24, 1, { feedback: ['sour'], rating: 2, suggestedGrind: 22 }), brew('bean', 26, 3, { feedback: ['sour'], rating: 1 }),
    ])!
    expect(suggested.value).toBe(22)
    expect(suggested.reason).toContain('Suggested')
    const reference = recommendGrind('bean', grinderItem, 'kasuya-46', [brew('bean', 23, 1, { feedback: ['perfect'], rating: 5 })])!
    expect(reference.value).toBe(23)
    expect(reference.reason).toContain('reference')
    const recipe = recommendGrind(null, grinderItem, 'kasuya-46', [
      brew(null, 18, 1, { recipeId: 'rao-v60' }), brew(null, 24, 2, { feedback: ['sour'], suggestedGrind: 20 }),
    ])!
    expect(recipe.value).toBe(20)
    expect(recipe.reason).toContain('of this recipe')
    const unknownBean = recommendGrind('never-brewed', grinderItem, 'kasuya-46', [
      brew(null, 18, 1, { recipeId: 'rao-v60' }), brew(null, 27, 2),
    ])!
    expect(unknownBean.value).toBe(27)
  })

  it('remembers the last selection and ignores tampered ids', () => {
    vi.stubGlobal('localStorage', memoryStorage())
    const first = new BrewSetup(() => PRESET_RECIPES)
    first.patch({ beanId: 'bean-a', grinderId: 'g1' })
    first.select(PRESET_RECIPES[1])
    const second = new BrewSetup(() => PRESET_RECIPES)
    expect(second.value.beanId).toBe('bean-a')
    expect(second.value.grinderId).toBe('g1')
    expect(second.value.recipe.id).toBe(PRESET_RECIPES[1].id)
    localStorage.setItem('brewlog.setup', JSON.stringify({ beanId: '<img src=x onerror=alert(1)>', recipeId: 42 }))
    const third = new BrewSetup(() => PRESET_RECIPES)
    expect(third.value.beanId).toBeNull()
    expect(third.value.recipe.id).toBe(PRESET_RECIPES[0].id)
    localStorage.setItem('brewlog.setup', '{not json')
    expect(new BrewSetup(() => PRESET_RECIPES).value.beanId).toBeNull()
  })

  it('keeps an explicitly set grind until bean or grinder change', () => {
    vi.stubGlobal('localStorage', memoryStorage())
    const setup = new BrewSetup(() => PRESET_RECIPES)
    setup.patch({ beanId: 'bean-a', grinderId: 'g1' })
    setup.pinGrind(24)
    expect(setup.value.grindValue).toBe(24)
    expect(setup.isGrindPinned).toBe(true)
    setup.patch({ beanId: 'bean-b' })
    expect(setup.isGrindPinned).toBe(false)
  })

  it('shows the grind with the grinder scale saved in the brew', () => {
    const b = brew(null, 24, 0)
    expect(grindDisplay(b)).toBe('24 clicks')
    expect(grindDisplay({ ...b, grinderSpec: null, grindValue: null, grindSetting: 'medium-fine' })).toBe('medium-fine')
  })

  it('continues with the gear and beans of the latest brew after a restore', () => {
    vi.stubGlobal('localStorage', memoryStorage())
    const setup = new BrewSetup(() => PRESET_RECIPES)
    setup.patch({ brewerId: 'gone', grinderId: 'g1' })
    const gear = (id: string, type: Equipment['type']): Equipment => ({ ...grinderItem, id, name: id, type })
    setup.adopt({
      version: 1, customRecipes: [],
      equipment: [gear('v60', 'brewer'), gear('switch', 'brewer'), gear('g1', 'grinder'), gear('paper', 'filter')],
      beans: [newBean({ id: 'old', name: 'Old', createdAt: 1 }), newBean({ id: 'new', name: 'New', createdAt: 2 })],
      brews: [brew('old', 20, 9, { brewerId: 'v60' }), brew('old', 22, 1, { brewerId: 'switch' })],
    })
    expect(setup.value).toMatchObject({ brewerId: 'switch', grinderId: 'g1', filterId: 'paper', beanId: 'old', grindValue: null })
    setup.adopt({ version: 1, customRecipes: [], equipment: [], brews: [], beans: [newBean({ id: 'b2', name: 'Fresh' })] })
    expect(setup.value).toMatchObject({ brewerId: null, grinderId: null, filterId: null, beanId: 'b2' })
  })

  it('clears deleted gear and picks newly added gear', () => {
    vi.stubGlobal('localStorage', memoryStorage())
    const setup = new BrewSetup(() => PRESET_RECIPES)
    setup.patch({ grinderId: null })
    setup.reconcileGear('grinder', ['g1'])
    expect(setup.value.grinderId).toBeNull()
    setup.reconcileGear('grinder', ['g1', 'g2'])
    expect(setup.value.grinderId).toBe('g2')
    setup.reconcileGear('grinder', ['g1'])
    expect(setup.value.grinderId).toBeNull()
  })
})

describe('brew engine', () => {
  class FakeScale implements ScaleCommands {
    commands: string[] = []
    isReady = true
    tare() { this.commands.push('tare') }
    prepareForBrew() { this.commands.push('prepare') }
    prepareForDosing() { this.commands.push('dose') }
    dosingFinished() { this.commands.push('doseDone') }
    brewStarted() { this.commands.push('start') }
    brewFinished() { this.commands.push('stop') }
  }

  it('auto-starts, pings before the target and chimes the next step once', () => {
    const recipe = PRESET_RECIPES.find((r) => r.id === 'everyday-3-pour')!
    let now = 0
    const cues: [number, BrewCue][] = []
    const scale = new FakeScale()
    const session = new BrewSession(recipe, scale, () => DEFAULT_SETTINGS, (c) => cues.push([now, c]), () => now)
    session.ready()
    expect(scale.commands).toEqual(['prepare'])
    let weight = 0
    for (let step = 0; step < 150; step++) {
      now = step * 100
      if (now >= 1000 && weight < 51) weight += 0.5
      session.ingest(weight, now)
      session.tick()
    }
    expect(session.phase).toBe('brewing')
    expect(scale.commands).toContain('start')
    const ping = cues.find(([, c]) => c === 'target')!
    expect(ping[0]).toBeLessThan(11_000)
    for (let step = 0; step < 200; step++) {
      now = 15_000 + step * 100
      session.ingest(weight, now)
      session.tick()
    }
    expect(cues.filter(([, c]) => c === 'nextStep')).toHaveLength(1)
    session.finish()
    expect(session.phase).toBe('finished')
    expect(scale.commands).toContain('stop')
  })

  it('estimates flow with a least-squares slope', () => {
    const readings = Array.from({ length: 12 }, (_, i) => [i * 100, i * 0.5] as const)
    expect(slope(readings, 1.2, 1100)).toBeCloseTo(5, 2)
    expect(slope([], 1.2, 0)).toBe(0)
  })
})
