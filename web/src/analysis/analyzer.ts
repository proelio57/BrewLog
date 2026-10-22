import { fmt1, formatDate, mmss, roundHalfAway } from '../domain/format'
import {
  type FilterFlow, type GrinderSpec, type MachineSample, type RoastLevel, type TasteFeedback, type WeightSample,
  adjustGrind, formatGrind, formatGrindDelta, roastIndex as indexOfRoast,
} from '../domain/models'
import { pourSteps, ratio as recipeRatio, ratioText, isPour, type Recipe, type RecipeStep } from '../domain/recipe'
import { clearerAlternative } from '../domain/recipeFilter'
import { analyzeEspresso } from './espresso'

// Rule-based (no AI) brew analysis. 1:1 port of BrewAnalyzer.swift / BrewAnalyzer.kt.
// Keep keys, thresholds and priorities identical across platforms (the tests share the same scenarios).

export interface GrinderContext { name: string; spec: GrinderSpec; currentValue: number | null }

/** A previous brew of the same bean (and grinder), used to bracket the grind setting. */
export interface PastBrew {
  date: number
  recipeId: string
  grindValue: number | null
  rating: number
  feedback: TasteFeedback[]
  totalTime: number
}

export interface AnalysisInput {
  recipe: Recipe
  samples: WeightSample[]
  usedScale: boolean
  totalTime: number
  finalWeight: number
  dose: number
  waterTemp: number
  roastLevel: RoastLevel | null
  daysOffRoast: number | null
  filterName: string
  filterFlow: FilterFlow | null
  filterIdealRoast: RoastLevel | null
  grinder: GrinderContext | null
  feedback: TasteFeedback[]
  /** Earlier brews with the same bean and grinder, newest first. */
  history: PastBrew[]
  /** Espresso: pressure, temperature and flow from the machine or pressure sensor. */
  machine?: MachineSample[]
  /** Recipes BrewLog may point to (built-in list); the brewed recipe itself is never suggested. */
  alternatives?: Recipe[]
}

export type FindingLevel = 'good' | 'info' | 'warning'
const LEVEL_ORDER: Record<FindingLevel, number> = { good: 0, info: 1, warning: 2 }
export interface Finding { level: FindingLevel; title: string; detail: string }

export interface Suggestion {
  key: string
  title: string
  detail: string
  priority: number
  /** What in the brew data triggered this suggestion (empty = general advice). */
  evidence: string[]
  grindTarget: number | null
}

export interface PourResult {
  number: number
  stepIndex: number
  step: RecipeStep
  target: number
  actualStart: number | null
  actualEnd: number | null
  reached: number | null
  averageFlow: number | null
}
export const startDelta = (p: PourResult): number | null => (p.actualStart != null ? p.actualStart - p.step.time : null)
export const weightDelta = (p: PourResult): number | null => (p.reached != null ? p.reached - p.target : null)

export type ExtractionLean = 'under' | 'balanced' | 'over' | 'uneven' | 'unknown'
export const LEAN_TITLES: Record<ExtractionLean, string> = {
  under: 'Leaning under-extracted',
  balanced: 'Balanced extraction',
  over: 'Leaning over-extracted',
  uneven: 'Uneven extraction',
  unknown: 'Mixed signals',
}

export interface BrewAnalysis {
  pours: PourResult[]
  findings: Finding[]
  suggestions: Suggestion[]
  lean: ExtractionLean
  headline: string
  /** Grind to use next time (pre-filled in the brew setup for this bean and grinder). */
  suggestedGrind: number | null
}

// MARK: - Pour detection

export interface Segment { start: number; end: number; startWeight: number; endWeight: number }
const duration = (s: Segment) => Math.max(s.end - s.start, 0.1)
const poured = (s: Segment) => s.endWeight - s.startWeight

/** Smoothed flow (g/s) for each sample using a ~1 s backward window (used for analysis). */
export function flows(samples: WeightSample[]): number[] {
  const result: number[] = []
  let j = 0
  for (let i = 0; i < samples.length; i++) {
    while (j < i && samples[i].t - samples[j].t > 1) j++
    const dt = samples[i].t - samples[j].t
    result.push(dt > 0.3 ? (samples[i].w - samples[j].w) / dt : 0)
  }
  return result
}

/** Flow (g/s) centred on each sample (±half the window). Lines up with the weight curve, so used for charts. */
export function centeredFlows(samples: WeightSample[], window = 1): number[] {
  if (samples.length <= 1) return samples.map(() => 0)
  const half = window / 2
  const result = new Array<number>(samples.length).fill(0)
  let lo = 0
  let hi = 0
  for (let i = 0; i < samples.length; i++) {
    const t = samples[i].t
    while (lo < i && samples[lo].t < t - half) lo++
    if (hi < i) hi = i
    while (hi + 1 < samples.length && samples[hi + 1].t <= t + half) hi++
    const dt = samples[hi].t - samples[lo].t
    result[i] = dt >= 0.3 ? (samples[hi].w - samples[lo].w) / dt : 0
  }
  return result
}

/** Splits the weight curve into pour segments (periods where weight rises). */
export function detectSegments(samples: WeightSample[]): Segment[] {
  if (samples.length <= 5) return []
  const flow = flows(samples)
  const raw: [number, number][] = []
  let inPour = false
  let startIndex = 0
  let lowSince: number | null = null

  for (let i = 0; i < samples.length; i++) {
    if (!inPour) {
      if (flow[i] > 1) {
        inPour = true
        lowSince = null
        // Walk back to where the weight actually started rising.
        let windowStart = 0
        for (let k = 0; k < samples.length; k++) if (samples[k].t <= samples[i].t - 1) windowStart = k
        const base = samples[windowStart].w
        let k = i
        while (k > windowStart && samples[k - 1].w > base + 0.3) k--
        startIndex = Math.max(k - 1, 0)
      }
    } else if (flow[i] < 0.4) {
      const low: number = lowSince ?? i
      lowSince = low
      if (samples[i].t - samples[low].t >= 0.8) {
        raw.push([startIndex, i])
        inPour = false
        lowSince = null
      }
    } else {
      lowSince = null
    }
  }
  if (inPour) raw.push([startIndex, samples.length - 1])

  const segments = raw.map(([from, to]) => {
    let peak = -Infinity
    for (let i = from; i <= to; i++) peak = Math.max(peak, samples[i].w)
    let endIndex = to
    for (let i = from; i <= to; i++) {
      if (samples[i].w >= peak - 0.3) {
        endIndex = i
        break
      }
    }
    return { start: samples[from].t, end: samples[endIndex].t, startWeight: samples[from].w, endWeight: peak }
  })

  // Merge segments separated by tiny pauses.
  const merged: Segment[] = []
  for (const segment of segments) {
    const last = merged[merged.length - 1]
    if (last && segment.start - last.end < 1.5) {
      merged[merged.length - 1] = { ...last, end: segment.end, endWeight: Math.max(last.endWeight, segment.endWeight) }
    } else {
      merged.push(segment)
    }
  }
  return merged.filter((s) => poured(s) >= 2)
}

/** Splits continuous pours that run through an intermediate target (e.g. pouring 0:45→1:45 without pausing). */
export function splitAtTargets(segments: Segment[], samples: WeightSample[], recipe: Recipe): Segment[] {
  const pours = pourSteps(recipe)
  if (pours.length <= 1) return segments
  const result: Segment[] = []
  for (const segment of segments) {
    let current = segment
    for (let offset = 0; offset < pours.length - 1; offset++) {
      const target = pours[offset].target
      if (target == null) continue
      const nextTime = pours[offset + 1].time
      if (current.startWeight >= target - 5 || current.endWeight <= target + 5) continue
      if (nextTime <= current.start - 10 || nextTime >= current.end + 10) continue
      const start = current.start
      const crossing = samples.find((s) => s.t >= start && s.w >= target)
      if (!crossing) continue
      result.push({ start: current.start, end: crossing.t, startWeight: current.startWeight, endWeight: crossing.w })
      current = { start: crossing.t, end: current.end, startWeight: crossing.w, endWeight: current.endWeight }
    }
    result.push(current)
  }
  return result.filter((s) => poured(s) >= 2)
}

export function matchPours(recipe: Recipe, segments: Segment[]): PourResult[] {
  const pourIndices = recipe.steps.map((s, i) => (isPour(s.kind) && s.target != null ? i : -1)).filter((i) => i >= 0)
  const assigned = new Map<number, Segment[]>()
  let minPosition = 0
  for (const segment of segments) {
    if (minPosition >= pourIndices.length) break
    let best = minPosition
    let bestDistance = Infinity
    for (let position = minPosition; position < pourIndices.length; position++) {
      const distance = Math.abs(segment.start - recipe.steps[pourIndices[position]].time)
      if (distance < bestDistance) {
        bestDistance = distance
        best = position
      }
    }
    const list = assigned.get(pourIndices[best]) ?? []
    list.push(segment)
    assigned.set(pourIndices[best], list)
    minPosition = best
  }

  let pourCounter = 0
  return pourIndices.map((index) => {
    const step = recipe.steps[index]
    // The bloom is "B"; pours after it are numbered 1, 2, 3…
    const number = step.kind === 'bloom' ? 0 : ++pourCounter
    const result: PourResult = {
      number, stepIndex: index, step, target: step.target ?? 0,
      actualStart: null, actualEnd: null, reached: null, averageFlow: null,
    }
    const segs = assigned.get(index)
    if (segs?.length) {
      const first = segs[0]
      const last = segs[segs.length - 1]
      const pouredTime = segs.reduce((sum, s) => sum + duration(s), 0)
      result.actualStart = first.start
      result.actualEnd = last.end
      result.reached = last.endWeight
      result.averageFlow = (last.endWeight - first.startWeight) / Math.max(pouredTime, 0.5)
    }
    return result
  })
}

// MARK: - Main analysis

export function analyze(input: AnalysisInput): BrewAnalysis {
  if (input.recipe.method === 'espresso') return analyzeEspresso(input)
  const recipe = input.recipe
  const samples = input.samples
  const hasCurve = input.usedScale && samples.length > 10

  let segments: Segment[] = []
  let pours: PourResult[] = []
  if (hasCurve) {
    segments = splitAtTargets(detectSegments(samples), samples, recipe)
    pours = matchPours(recipe, segments)
  }

  const tolerance = Math.max(15, recipe.targetTime * 0.08)
  const timeDelta = input.totalTime - recipe.targetTime
  const ratio = input.dose > 0 ? input.finalWeight / input.dose : 0

  const totalPoured = segments.reduce((sum, s) => sum + poured(s), 0)
  const totalPourTime = segments.reduce((sum, s) => sum + duration(s), 0)
  const averageFlow = totalPourTime > 2 ? totalPoured / totalPourTime : null

  const valveRecipe = recipe.steps.some((s) => s.kind === 'openValve' || s.valve === 'closed')
  let drawdown: number | null = null
  let expectedDrawdown: number | null = null
  // Finish was tapped (almost) right after the last pour, so the total time doesn't include the drawdown.
  let drawdownMissing = false
  const lastSegment = segments[segments.length - 1]
  if (valveRecipe) {
    const open = [...recipe.steps].reverse().find((s) => s.kind === 'openValve')
    if (open) {
      drawdown = input.totalTime - open.time
      expectedDrawdown = recipe.targetTime - open.time
    }
  } else if (lastSegment && input.totalTime - lastSegment.end < 5) {
    drawdownMissing = true
  } else if (lastSegment) {
    drawdown = input.totalTime - lastSegment.end
    const planned = pourSteps(recipe)
    const last = planned[planned.length - 1]
    if (last?.target != null) {
      const previousTarget = planned.length > 1 ? planned[planned.length - 2].target ?? 0 : 0
      const idealFlow = Math.max((recipe.flowMin + recipe.flowMax) / 2, 1)
      expectedDrawdown = Math.max(recipe.targetTime - (last.time + (last.target - previousTarget) / idealFlow), 20)
    }
  }

  const bloomStep = recipe.steps.find((s) => s.kind === 'bloom')
  let bloomRatio: number | null = null
  let bloomDuration: number | null = null
  if (bloomStep?.target != null && input.dose > 0) {
    const actual = pours[0]?.reached ?? bloomStep.target
    bloomRatio = actual / input.dose
    const planned = pourSteps(recipe)
    if (pours.length > 1) bloomDuration = pours[1].actualStart ?? pours[1].step.time
    else if (planned.length > 1) bloomDuration = planned[1].time
  }

  // Signals (total time is only trusted when the drawdown was recorded)
  const timeLong = !drawdownMissing && timeDelta > tolerance
  const timeShort = !drawdownMissing && timeDelta < -tolerance
  const timeVeryOff = !drawdownMissing && Math.abs(timeDelta) > tolerance * 2
  const drawdownSlow = drawdown != null && expectedDrawdown != null && drawdown > expectedDrawdown + 25
  const drawdownFast = drawdown != null && expectedDrawdown != null && drawdown < expectedDrawdown - 25
  const flowFast = averageFlow != null && averageFlow > recipe.flowMax * 1.15
  const flowSlow = averageFlow != null && averageFlow < recipe.flowMin * 0.85
  const roastIndex = input.roastLevel != null ? indexOfRoast(input.roastLevel) : null
  const tempLow = input.waterTemp > 0 &&
    (input.waterTemp < recipe.temperature - 2.5 || ((roastIndex ?? 2) <= 1 && input.waterTemp < 92))
  const tempHigh = input.waterTemp > 0 &&
    (input.waterTemp > recipe.temperature + 2.5 || ((roastIndex ?? 0) >= 3 && input.waterTemp > 93))
  const targetRatio = recipeRatio(recipe)
  const ratioLow = ratio > 0 && ratio < targetRatio - 0.7
  const ratioHigh = ratio > 0 && ratio > targetRatio + 0.7
  const bloomSmall = bloomRatio != null && bloomRatio < 1.8
  const bloomShort = bloomDuration != null && bloomDuration < 25
  const tooFresh = input.daysOffRoast != null && input.daysOffRoast < 4
  const stale = input.daysOffRoast != null && input.daysOffRoast > 45
  const filterSlowish = input.filterFlow === 'slow' || input.filterFlow === 'medium'
  const filterFast = input.filterFlow === 'fast'

  // MARK: Findings
  const findings: Finding[] = []
  const planned = `${mmss(input.totalTime)} vs ${mmss(recipe.targetTime)} planned.`
  if (drawdownMissing) {
    findings.push({ level: 'info', title: 'Drawdown not recorded',
      detail: 'Finish was tapped right after the last pour. Tap Finish when the bed is dry so total time and drawdown can be analysed.' })
  } else if (Math.abs(timeDelta) <= tolerance) {
    findings.push({ level: 'good', title: 'Brew time on target', detail: planned })
  } else {
    findings.push({ level: 'warning',
      title: timeLong ? `Brew ran long (+${Math.trunc(timeDelta)} s)` : `Brew finished fast (−${Math.trunc(-timeDelta)} s)`,
      detail: `${planned} Contact time is one of the biggest extraction levers.` })
  }
  if (drawdown != null && expectedDrawdown != null) {
    if (drawdownSlow) {
      findings.push({ level: 'warning', title: 'Slow drawdown',
        detail: `${mmss(drawdown)} after the last pour (expected about ${mmss(expectedDrawdown)}). Usually caused by a fine grind, lots of fines, a slow paper or too much agitation at the end.` })
    } else if (drawdownFast) {
      findings.push({ level: 'info', title: 'Fast drawdown',
        detail: `${mmss(drawdown)} after the last pour (expected about ${mmss(expectedDrawdown)}). The water passed through quickly, so there was less contact time.` })
    }
  }
  if (bloomRatio != null) {
    findings.push(bloomSmall
      ? { level: 'warning', title: `Small bloom (${fmt1(bloomRatio)}× dose)`, detail: 'Aim for 2–3× the coffee weight so that all grounds are wet and degas evenly.' }
      : { level: 'good', title: `Bloom ${fmt1(bloomRatio)}× dose`, detail: 'Enough water to saturate the bed.' })
  }
  if (bloomDuration != null && bloomShort) {
    findings.push({ level: 'info', title: `Short bloom (${Math.trunc(bloomDuration)} s)`, detail: '30–45 s gives CO₂ time to escape so water can extract evenly.' })
  }
  for (const pour of pours) {
    const label = pour.step.kind === 'bloom' ? 'Bloom' : `Pour ${pour.number}`
    if (pour.actualStart == null) {
      findings.push({ level: 'info', title: `${label} not detected`, detail: `No clear pour around ${mmss(pour.step.time)}.` })
      continue
    }
    const sd = startDelta(pour)
    if (sd != null && Math.abs(sd) > 5 && pour.step.time > 0) {
      findings.push({ level: 'info', title: `${label} started ${roundHalfAway(Math.abs(sd))} s ${sd > 0 ? 'late' : 'early'}`,
        detail: `Planned at ${mmss(pour.step.time)}, started at ${mmss(pour.actualStart)}.` })
    }
    const wd = weightDelta(pour)
    if (wd != null) {
      const weightTolerance = Math.max(3, pour.target * 0.04)
      const reached = roundHalfAway(pour.reached ?? 0)
      if (wd > weightTolerance) {
        findings.push({ level: 'warning', title: `${label} overpoured by ${roundHalfAway(wd)} g`,
          detail: `Reached ${reached} g, target ${Math.trunc(pour.target)} g. Try a bigger ping buffer in Settings.` })
      } else if (wd < -weightTolerance) {
        findings.push({ level: 'info', title: `${label} underpoured by ${roundHalfAway(Math.abs(wd))} g`,
          detail: `Reached ${reached} g, target ${Math.trunc(pour.target)} g.` })
      }
    }
  }
  if (averageFlow != null) {
    const range = `${Math.trunc(recipe.flowMin)}–${Math.trunc(recipe.flowMax)} g/s`
    if (flowFast) findings.push({ level: 'warning', title: `Fast pours (${fmt1(averageFlow)} g/s)`, detail: `The recipe suggests ${range}. Fast, high pours add agitation and can dig channels.` })
    else if (flowSlow) findings.push({ level: 'info', title: `Slow pours (${fmt1(averageFlow)} g/s)`, detail: `The recipe suggests ${range}. Very gentle pours add little agitation and the slurry cools down.` })
    else findings.push({ level: 'good', title: `Pour rate on point (${fmt1(averageFlow)} g/s)`, detail: `Within the recipe's ${range}.` })
  }
  if (input.usedScale) {
    const delta = input.finalWeight - recipe.water
    if (Math.abs(delta) > Math.max(4, recipe.water * 0.02)) {
      findings.push({ level: 'warning', title: `Total water ${delta > 0 ? 'over' : 'under'} by ${roundHalfAway(Math.abs(delta))} g`,
        detail: `Brewed at 1:${fmt1(ratio)} instead of ${ratioText(recipe)}. More water = weaker but more extracted. Less water = stronger.` })
    } else {
      findings.push({ level: 'good', title: `Ratio 1:${fmt1(ratio)}`, detail: `Right on the recipe's ${ratioText(recipe)}.` })
    }
  }
  if (input.waterTemp > 0) {
    const temp = Math.trunc(input.waterTemp)
    if (roastIndex != null && roastIndex <= 1 && input.waterTemp < 92) {
      findings.push({ level: 'warning', title: 'Cool water for a light roast', detail: `Light roasts are dense and extract best at 93–100 °C. You used ${temp} °C.` })
    } else if (roastIndex != null && roastIndex >= 3 && input.waterTemp > 93) {
      findings.push({ level: 'warning', title: 'Hot water for a dark roast', detail: `Dark roasts extract easily. 83–90 °C keeps bitterness down. You used ${temp} °C.` })
    } else if (Math.abs(input.waterTemp - recipe.temperature) > 2.5) {
      findings.push({ level: 'info', title: `Water ${temp} °C (recipe ${Math.trunc(recipe.temperature)} °C)`, detail: 'Hotter water extracts more. Cooler water extracts less.' })
    }
  }
  if (input.daysOffRoast != null) {
    if (tooFresh) findings.push({ level: 'info', title: `Very fresh beans (${input.daysOffRoast} days)`, detail: 'Trapped CO₂ pushes water away and causes uneven extraction. Light roasts often peak 7–21 days after roasting.' })
    else if (stale) findings.push({ level: 'info', title: `Beans are ${input.daysOffRoast} days off roast`, detail: 'Aromatics fade over time, so cups get flatter and more papery.' })
  }
  if (input.filterIdealRoast != null && roastIndex != null) {
    if (input.filterIdealRoast === 'dark' && roastIndex <= 1) {
      findings.push({ level: 'info', title: 'Dark-roast paper with a light roast', detail: `${input.filterName} is tuned for dark roasts at about 83 °C. With light roasts, a T-92 or T-90 usually extracts better.` })
    } else if (input.filterIdealRoast === 'light' && roastIndex >= 3) {
      findings.push({ level: 'info', title: 'Light-roast paper with a dark roast', detail: `${input.filterName} is tuned for light roasts. A T-83 or T-90 brings more body and less harshness to darker roasts.` })
    }
  }
  if (input.grinder == null) {
    findings.push({ level: 'info', title: 'No grinder selected', detail: 'Add your grinder in Gear and log the setting so suggestions can say exactly how many clicks to change.' })
  } else if (input.grinder.currentValue == null) {
    findings.push({ level: 'info', title: 'Grind setting not logged', detail: 'Log the grind setting so suggestions can give you an exact number.' })
  }

  // MARK: Extraction lean (data only)
  let over = 0
  let under = 0
  if (timeLong) over += 1
  if (timeShort) under += 1
  if (drawdownSlow) over += 0.5
  if (drawdownFast) under += 0.5
  if (tempHigh) over += 0.5
  if (tempLow) under += 0.5
  if (ratioHigh) over += 0.5
  if (ratioLow) under += 0.5
  if (bloomSmall || bloomShort) under += 0.3
  if (flowFast) over += 0.3
  let lean: ExtractionLean =
    over - under >= 1 ? 'over' : under - over >= 1 ? 'under' : over < 0.5 && under < 0.5 ? 'balanced' : 'unknown'

  const feedback = new Set(input.feedback)
  const sour = feedback.has('sour')
  const bitter = feedback.has('bitter')
  const astringent = feedback.has('astringent')
  if (sour && (bitter || astringent)) lean = 'uneven'

  // MARK: Suggestions
  const suggestions = new Map<string, Suggestion>()
  const add = (key: string, title: string, detail: string, priority: number, evidence: string[] = [], grind: number | null = null) => {
    const existing = suggestions.get(key)
    if (existing && existing.priority >= priority) {
      suggestions.set(key, { ...existing, evidence: [...existing.evidence, ...evidence.filter((e) => !existing.evidence.includes(e))] })
      return
    }
    suggestions.set(key, { key, title, detail, priority, evidence, grindTarget: grind })
  }

  const timeEvidence = timeLong
    ? `Brew took ${mmss(input.totalTime)}, ${Math.trunc(timeDelta)} s longer than planned`
    : `Brew took ${mmss(input.totalTime)}, ${Math.trunc(-timeDelta)} s faster than planned`
  const avgFlowText = fmt1(averageFlow ?? 0)

  const grindSuggestion = (coarser: boolean, priority: number, evidence: string[]) => {
    const direction = coarser ? 'coarser' : 'finer'
    const multiplier = timeVeryOff ? 2 : 1
    const why = coarser
      ? 'A coarser grind slows extraction and speeds up drawdown, which reduces bitterness and harshness.'
      : 'A finer grind exposes more surface and slows the flow, so more sweetness and less sourness.'
    const grinder = input.grinder
    if (grinder && grinder.currentValue != null) {
      const value = grinder.currentValue
      const target = bracketed(coarser, value, grinder, input.history) ?? adjustGrind(grinder.spec, value, coarser, multiplier)
      add('grind', `Grind ${direction}: ${formatGrind(grinder.spec, target)}`,
        `Go from ${formatGrind(grinder.spec, value)} to ${formatGrind(grinder.spec, target)} on your ${grinder.name}. ${why}`, priority, evidence, target)
    } else if (grinder) {
      add('grind', `Grind ${direction}`,
        `Adjust your ${grinder.name} about ${formatGrindDelta(grinder.spec, grinder.spec.adjustStep * multiplier)} ${direction}. Log the setting next time for exact numbers. ${why}`,
        priority, evidence)
    } else {
      add('grind', `Grind ${direction}`, `Make a small step ${direction}. ${why} Add your grinder in Gear to get exact click recommendations.`, priority, evidence)
    }
  }

  const isFourSix = recipe.id.startsWith('kasuya-46')
  const isImmersion = recipe.steps.some((s) => s.valve === 'closed')

  if (lean === 'uneven') {
    add('evenness', 'Even out the extraction',
      'Sour and bitter together usually means channeling: some grounds over-extract while water rushes past others. Pour gently in the centre, avoid hitting the paper walls, and swirl after the bloom and the last pour to flatten the bed.',
      110, flowFast ? [`Average pour rate ${avgFlowText} g/s is above the recipe range`] : [])
    add('fines', 'Reduce fines', 'Lots of fines clog the paper and channel. Try a slightly coarser grind, or sift and remove the dust.', 70)
  }

  if (sour) {
    if (timeShort) grindSuggestion(false, 100, [timeEvidence])
    else if (timeLong) {
      add('evenness', 'Even out the extraction',
        "The brew was slow but still sour. That points to uneven extraction (channeling or a clogged bed), not a grind that's too coarse. Pour more gently and centrally, swirl to flatten the bed, and check for fines.",
        95, [timeEvidence])
    }
    if (tempLow) {
      add('temp-up', 'Use hotter water', `Try ${(roastIndex ?? 99) <= 1 ? '96–100' : '93–96'} °C. Hotter water dissolves more of the sugars and balances acidity.`,
        90, [`Water was ${Math.trunc(input.waterTemp)} °C`])
    }
    if (bloomSmall || bloomShort) {
      add('bloom', 'Bloom longer and bigger', 'Use 2–3× the dose in water for 40–45 s and swirl so no dry clumps remain.', 80,
        [bloomRatio != null ? `Bloom was ${fmt1(bloomRatio)}× dose` : null, bloomDuration != null ? `Bloom lasted ${Math.trunc(bloomDuration)} s` : null]
          .filter((e): e is string => e !== null))
    }
    if (ratioLow) add('ratio-up', 'Use the full amount of water', `A tighter ratio extracts less. Aim for ${ratioText(recipe)}.`, 70, [`Brewed at 1:${fmt1(ratio)}`])
    if (flowSlow && !timeLong) {
      add('agitation-up', 'Add a little agitation', 'Pour a bit faster or give the brewer a gentle swirl after the bloom and the last pour.', 60, [`Average pour rate ${avgFlowText} g/s`])
    }
    if (filterFast && (timeShort || drawdownFast)) {
      add('filter-slower', 'Try a medium-flow paper', `${input.filterName} drains fast. CAFEC T-90 or the Hario standard paper keep the coffee in contact longer.`, 55, ['Fast drawdown with a fast paper'])
    }
    if (tooFresh) add('rest', 'Let the beans rest', 'Wait a few more days. Fresh beans release CO₂, which causes uneven extraction and sharp acidity.', 50, [`${input.daysOffRoast} days off roast`])
    if (isFourSix) add('46-sweet', 'Shift the 4:6 balance toward sweetness', 'In 4:6 the first 40% controls the balance. Make the first pour smaller and the second larger (e.g. 50 g then 70 g).', 65)
    if (lean !== 'uneven' && !timeLong && !suggestions.has('grind')) grindSuggestion(false, 75, [])
    if (!suggestions.has('temp-up') && input.waterTemp > 0 && input.waterTemp < 99) {
      add('temp-up', 'Raise the temperature 2–3 °C', 'A small temperature increase gives a little more extraction without changing anything else.', 58)
    }
  }

  if (bitter) {
    if (timeLong) grindSuggestion(true, 100, [timeEvidence])
    else if (timeShort) {
      add('evenness', 'Even out the extraction', 'The brew was quick but still bitter. That usually means channeling, or the water is too hot for this roast. Pour more gently and centrally.', 85, [timeEvidence])
    }
    if (drawdownSlow && drawdown != null && expectedDrawdown != null) {
      add('drawdown', 'Speed up the drawdown',
        'Swirl gently instead of stirring at the end, and avoid pouring onto the paper walls.' + (filterSlowish ? ' A faster paper (CAFEC Abaca+, T-92, Hario tabbed or Sibarist FAST) also helps.' : ''),
        80, [`Drawdown ${mmss(drawdown)} vs about ${mmss(expectedDrawdown)} expected`])
    }
    if (tempHigh) {
      add('temp-down', 'Lower the water temperature', `Try ${(roastIndex ?? -1) >= 3 ? '85–90' : '90–92'} °C. Darker roasts dissolve easily and turn harsh when the water is too hot.`,
        88, [`Water was ${Math.trunc(input.waterTemp)} °C`])
    }
    if (flowFast) add('gentle', 'Pour more gently', 'Lower the kettle and slow the stream. Turbulent pours over-agitate the bed and pull out bitter compounds.', 75, [`Average pour rate ${avgFlowText} g/s`])
    if (ratioHigh) add('ratio-down', "Don't overshoot the water", `Extra water keeps extracting the late, bitter compounds. Stop at ${Math.trunc(recipe.water)} g.`, 60, [`Brewed at 1:${fmt1(ratio)}`])
    if (input.filterIdealRoast === 'light' && (roastIndex ?? 0) >= 3) {
      add('filter-roast', 'Use a dark-roast paper', 'CAFEC T-83 (or T-90) suits darker roasts better and gives more body with less harshness.', 50)
    }
    if (stale) add('fresh', 'Use fresher beans', 'Old beans lose sweetness and aromatics, so bitterness stands out more.', 40, [`${input.daysOffRoast} days off roast`])
    if (!suggestions.has('grind') && !timeShort && lean !== 'uneven') grindSuggestion(true, 74, [])
    if (!suggestions.has('temp-down') && input.waterTemp > 88) {
      add('temp-down', 'Lower the temperature 2–3 °C', 'Slightly cooler water extracts a little less and softens bitterness.', 56)
    }
  }

  if (astringent && lean !== 'uneven') {
    if (flowFast) {
      add('gentle', 'Pour more gently', 'Drying, rough cups are often caused by aggressive pours that channel. Lower the kettle and keep a thin, steady stream.', 95, [`Average pour rate ${avgFlowText} g/s`])
    }
    if (timeLong || drawdownSlow) {
      grindSuggestion(true, 85, [timeLong ? timeEvidence : 'Slow drawdown'])
      add('fines', 'Reduce fines', 'Fines clog the paper and over-extract into astringency. Sift them out or try a slightly coarser grind.', 70)
    }
    add('walls', 'Pour in the centre and flatten the bed', 'Avoid pouring onto the paper walls (water bypasses the coffee), and finish with a gentle swirl.', 65)
    add('rinse', 'Rinse the paper well', 'Rinse with plenty of hot water to remove paper taste and preheat the brewer.', 40)
  }

  if (feedback.has('weak')) {
    if (ratioHigh || (input.usedScale && input.finalWeight > recipe.water * 1.04)) {
      add('ratio-strength', 'Stop at the target water', 'You used more water than planned, which dilutes the cup.', 92, [`Brewed at 1:${fmt1(ratio)}`])
    }
    if (timeShort) grindSuggestion(false, 80, [timeEvidence])
    add('dose-up', 'Use a bit more coffee', `Strength mostly depends on the ratio. Try +1 g of coffee (about 1:${fmt1(Math.max(targetRatio - 1, 12))}) with the same water.`, 76)
    if (isFourSix) add('46-strength', 'Split the last 60% into more pours', 'In 4:6 the number of pours in the second phase sets strength. 3 → 4 pours makes it stronger.', 70)
    if (isImmersion) add('steep-longer', 'Steep longer', 'Open the valve 20–30 s later for more strength and extraction.', 72)
  }

  if (feedback.has('strong')) {
    if (ratioLow || (input.usedScale && input.finalWeight < recipe.water * 0.96)) {
      add('ratio-strength', 'Use all of the water', 'You stopped short of the target water, so the cup is more concentrated.', 92, [`Brewed at 1:${fmt1(ratio)}`])
    }
    add('ratio-up-strength', 'Use a longer ratio', `Try about 1:${fmt1(targetRatio + 1)}. Use the same coffee with more water, or 1 g less coffee.`, 76)
    if (isFourSix) add('46-strength', 'Use fewer pours in the 60% phase', 'Two larger pours instead of three gives a lighter cup.', 70)
    if (isImmersion) add('steep-shorter', 'Steep shorter', 'Open the valve 20–30 s earlier.', 72)
  }

  if (feedback.has('flat')) {
    if (stale) add('fresh', 'Use fresher beans', 'Flat, hollow cups are the classic sign of beans that are past their peak.', 95, [`${input.daysOffRoast} days off roast`])
    if (tempLow) add('temp-up', 'Use hotter water', 'More heat extracts more aromatics and sweetness.', 85, [`Water was ${Math.trunc(input.waterTemp)} °C`])
    if (timeShort) grindSuggestion(false, 75, [timeEvidence])
    add('water', 'Check your water', 'Distilled or very soft water tastes flat, and very hard water dulls acidity. Aim for about 50–100 ppm hardness (e.g. a light-roast mineral recipe or a low-mineral bottled water).', 60)
    const advice = clarityAdvice(recipe, input)
    if (advice) add('clarity', advice.title, advice.detail, 45)
  }

  // History hint: point to the best-rated brew of this bean
  const negative = feedback.size > 0 && !feedback.has('perfect')
  const grinderContext = input.grinder
  if (negative && grinderContext) {
    const candidates = input.history.filter((h) => h.grindValue != null && (h.rating >= 4 || h.feedback.includes('perfect')))
    const best = candidates.reduce<PastBrew | null>((top, h) => (top == null || h.rating > top.rating ? h : top), null)
    if (best?.grindValue != null && best.grindValue !== grinderContext.currentValue) {
      add('history', `Your best brew of this bean: ${formatGrind(grinderContext.spec, best.grindValue)}`,
        `On ${formatDate(best.date)} it was rated ${best.rating}★ at ${formatGrind(grinderContext.spec, best.grindValue)} (${mmss(best.totalTime)}).`, 66)
    }
  }

  if (feedback.has('perfect')) {
    suggestions.clear()
    const grindText = grinderContext?.currentValue != null ? ` at ${formatGrind(grinderContext.spec, grinderContext.currentValue)}` : ''
    add('repeat', 'Repeat it', `This brew is saved as your reference${grindText}. BrewLog will suggest the same settings next time you brew this bean.`, 100)
  }

  const sorted = [...suggestions.values()].sort((a, b) => b.priority - a.priority)
  const suggestedGrind = feedback.has('perfect')
    ? input.grinder?.currentValue ?? null
    : sorted.find((s) => s.grindTarget != null)?.grindTarget ?? null

  let headline: string
  if (feedback.size === 0) {
    headline = lean === 'balanced' ? 'Everything went to plan. Now taste it and tell BrewLog how it was.'
      : lean === 'over' ? 'The data leans over-extracted: watch for bitterness.'
        : lean === 'under' ? 'The data leans under-extracted: watch for sourness.'
          : 'Taste it and tell BrewLog how it was to get tailored tips.'
  } else if (feedback.has('perfect')) headline = 'Nailed it. These settings are your reference for this coffee.'
  else if (lean === 'uneven') headline = 'Sour and bitter at the same time points to uneven extraction.'
  else if (sour && lean === 'under') headline = 'Under-extracted: the brew data agrees with the sourness.'
  else if (bitter && lean === 'over') headline = 'Over-extracted: the brew data agrees with the bitterness.'
  else if (sour || bitter) headline = "Here's what to change next time, most impactful first."
  else headline = 'A few tweaks for next time.'

  return {
    pours,
    findings: findings.map((f, i) => ({ f, i })).sort((a, b) => LEVEL_ORDER[b.f.level] - LEVEL_ORDER[a.f.level] || a.i - b.i).map((x) => x.f),
    suggestions: sorted,
    lean,
    headline,
    suggestedGrind,
  }
}

/**
 * If an earlier brew at a setting in the requested direction went too far the other way,
 * split the difference instead of jumping a full step.
 */
export function bracketed(coarser: boolean, current: number, grinder: GrinderContext, history: PastBrew[]): number | null {
  const spec = grinder.spec
  const isCoarser = (a: number, than: number) => (spec.finerIsLower ? a > than : a < than)
  const candidates = history.flatMap((past) => {
    const value = past.grindValue
    if (value == null || value === current) return []
    if (coarser) return isCoarser(value, current) && (past.feedback.includes('sour') || past.feedback.includes('weak')) ? [value] : []
    return !isCoarser(value, current) && (past.feedback.includes('bitter') || past.feedback.includes('astringent')) ? [value] : []
  })
  if (!candidates.length) return null
  const nearest = candidates.reduce((a, b) => (Math.abs(b - current) < Math.abs(a - current) ? b : a))
  const mid = roundHalfAway((current + nearest) / 2 / spec.step) * spec.step
  return mid === current || mid === nearest ? null : mid
}

/** "Flat" cup: point to a clearer recipe for the same brewer (never the one just brewed) and/or a fast paper. */
export function clarityAdvice(recipe: Recipe, input: AnalysisInput): { title: string; detail: string } | null {
  const alternative = clearerAlternative(recipe, input.alternatives ?? [])
  const paper = input.filterFlow === 'fast' ? null : 'A fast paper like CAFEC T-92 or Abaca+ brings out brighter, more defined flavours.'
  if (!alternative) return paper ? { title: 'Try a faster paper', detail: paper } : null
  const by = alternative.author ? ` by ${alternative.author}` : ''
  return {
    title: `Try ${alternative.name} for more clarity`,
    detail: `${alternative.name}${by} is cleaner and brighter than ${recipe.name}.${paper ? ` ${paper}` : ''}`,
  }
}
