import { fmt1, formatDate, grams, mmss, roundHalfAway } from '../domain/format'
import { adjustGrind, formatGrind, type MachineSample, type WeightSample } from '../domain/models'
import { ratio as recipeRatio, ratioText } from '../domain/recipe'
import { type AnalysisInput, type BrewAnalysis, type ExtractionLean, type Finding, type Suggestion, bracketed } from './analyzer'

// Port of EspressoAnalyzer.swift (rule-based, no AI):
//  • Shot time is mostly grind: fast + sour → grind finer, slow + bitter → grind coarser.
//  • At a good shot time the ratio does the fine-tuning: sour → let it run longer, bitter → stop earlier.
//  • Temperature is the third lever: hotter for sour or light roasts, cooler for bitter or dark roasts.
//  • Sour and bitter together, very early first drops or a sudden pressure drop → channeling → puck prep.
//  • Weak / strong is the ratio or the dose.

export const TIME_TOLERANCE = 3
export const RATIO_TOLERANCE = 0.2

/** Time of the first gram in the cup. */
export const firstDrops = (samples: WeightSample[]): number | null => samples.find((s) => s.w >= 1)?.t ?? null

export interface PressureSummary {
  peak: number
  /** Largest fall within 2 s while the pump was still pushing (not the ramp-down at the end). */
  suddenDrop: number
  dropTime: number | null
  averageTemperature: number | null
}

export function pressureSummary(machine: MachineSample[]): PressureSummary | null {
  if (machine.length < 4) return null
  const peakSample = machine.reduce((a, b) => (b.p > a.p ? b : a))
  if (peakSample.p < 1) return null
  const end = machine[machine.length - 1].t
  const window = machine.filter((s) => s.t >= peakSample.t && s.t <= end - 3)
  let drop = 0
  let dropTime: number | null = null
  window.forEach((sample, i) => {
    for (const later of window.slice(i + 1)) {
      if (later.t - sample.t > 2) break
      if (sample.p - later.p > drop) {
        drop = sample.p - later.p
        dropTime = later.t
      }
    }
  })
  const temps = machine.map((s) => s.c).filter((c): c is number => c != null)
  return { peak: peakSample.p, suddenDrop: drop, dropTime, averageTemperature: temps.length ? temps.reduce((a, b) => a + b, 0) / temps.length : null }
}

const LEVEL_ORDER = { good: 0, info: 1, warning: 2 } as const

export function analyzeEspresso(input: AnalysisInput): BrewAnalysis {
  const recipe = input.recipe
  const feedback = new Set(input.feedback)
  const hasCurve = input.usedScale && input.samples.length > 5
  const ratio = input.dose > 0 ? input.finalWeight / input.dose : 0
  const targetRatio = recipeRatio(recipe)
  const timeDelta = input.totalTime - recipe.targetTime
  const timeShort = timeDelta < -TIME_TOLERANCE
  const timeLong = timeDelta > TIME_TOLERANCE
  const timeVeryOff = Math.abs(timeDelta) > 8
  const ratioLow = ratio > 0 && ratio < targetRatio - RATIO_TOLERANCE
  const ratioHigh = ratio > targetRatio + RATIO_TOLERANCE
  const drops = hasCurve ? firstDrops(input.samples) : null
  const cupFlow = drops != null && input.totalTime - drops > 3 ? input.finalWeight / (input.totalTime - drops) : null
  const pressure = pressureSummary(input.machine ?? [])
  const targetPressure = recipe.pressure ?? 9
  const pressureLow = pressure != null && pressure.peak < targetPressure - 2
  const channelSign = (pressure != null && pressure.suddenDrop >= 2) || (drops != null && drops < 3)
  const roastIdx = input.roastLevel ? ['light', 'mediumLight', 'medium', 'mediumDark', 'dark'].indexOf(input.roastLevel) : null
  const temp = input.waterTemp

  // Findings
  const findings: Finding[] = []
  if (!timeShort && !timeLong) {
    findings.push({ level: 'good', title: `Shot time ${mmss(input.totalTime)}`, detail: `Right on the ${mmss(recipe.targetTime)} target (±${TIME_TOLERANCE} s).` })
  } else if (timeShort) {
    findings.push({ level: 'warning', title: `Fast shot: ${mmss(input.totalTime)}`,
      detail: `${Math.trunc(-timeDelta)} s faster than the ${mmss(recipe.targetTime)} target. Usually the grind is too coarse or the dose too low.` })
  } else {
    findings.push({ level: 'warning', title: `Slow shot: ${mmss(input.totalTime)}`,
      detail: `${Math.trunc(timeDelta)} s slower than the ${mmss(recipe.targetTime)} target. Usually the grind is too fine or the dose too high.` })
  }
  if (ratio > 0) {
    const text = `1:${fmt1(ratio)}`
    findings.push(ratioLow || ratioHigh
      ? { level: 'info', title: `Ratio ${text}, planned ${ratioText(recipe)}`, detail: `${grams(input.finalWeight)} in the cup instead of ${grams(recipe.water)}.` }
      : { level: 'good', title: `Ratio ${text}`, detail: `${grams(input.finalWeight)} from ${fmt1(input.dose)} g, as planned.` })
  }
  if (drops != null) {
    if (drops < 3) findings.push({ level: 'warning', title: `Early first drops (${mmss(drops)})`, detail: 'Coffee came through almost at once. That points to a coarse grind or a channel through the puck.' })
    else if (drops > 12) findings.push({ level: 'info', title: `Late first drops (${mmss(drops)})`, detail: 'A fine grind or a long pre-infusion. Fine if the taste is right.' })
    else findings.push({ level: 'good', title: `First drops at ${mmss(drops)}`, detail: 'A normal start for a shot.' })
  }
  if (cupFlow != null) {
    findings.push({ level: cupFlow >= recipe.flowMin && cupFlow <= recipe.flowMax ? 'good' : 'info', title: `Flow ${fmt1(cupFlow)} g/s`,
      detail: `Average in the cup after the first drops. Recipe: ${fmt1(recipe.flowMin)}–${fmt1(recipe.flowMax)} g/s.` })
  }
  if (pressure) {
    findings.push(pressureLow
      ? { level: 'warning', title: `Low pressure: ${fmt1(pressure.peak)} bar`, detail: `The recipe expects about ${Math.round(targetPressure)} bar. The puck gave little resistance: grind finer or dose a little more.` }
      : { level: 'good', title: `Peak pressure ${fmt1(pressure.peak)} bar`, detail: `Recipe: about ${Math.round(targetPressure)} bar.` })
    if (pressure.suddenDrop >= 2 && pressure.dropTime != null) {
      findings.push({ level: 'warning', title: `Pressure fell ${fmt1(pressure.suddenDrop)} bar at ${mmss(pressure.dropTime)}`, detail: 'A sudden drop during the shot usually means a channel opened in the puck.' })
    }
    if (pressure.averageTemperature != null && Math.abs(pressure.averageTemperature - temp) > 2) {
      findings.push({ level: 'info', title: `Brew temperature ${fmt1(pressure.averageTemperature)} °C`, detail: `Planned ${Math.trunc(temp)} °C. Let the machine heat up fully and flush before the shot.` })
    }
  }
  if (input.daysOffRoast != null) {
    if (input.daysOffRoast < 4) findings.push({ level: 'info', title: `Very fresh beans (${input.daysOffRoast} d)`, detail: 'Lots of CO₂ makes shots gush and channel. Espresso usually tastes best 7–21 days off roast.' })
    else if (input.daysOffRoast > 40) findings.push({ level: 'info', title: `Older beans (${input.daysOffRoast} d)`, detail: 'Flavour fades and shots run faster. Grind finer to compensate, or use fresher beans.' })
  }

  // Lean
  const sour = feedback.has('sour')
  const bitter = feedback.has('bitter') || feedback.has('astringent')
  let lean: ExtractionLean
  if ((sour && bitter) || (channelSign && !timeLong)) lean = 'uneven'
  else if (timeShort || pressureLow) lean = 'under'
  else if (timeLong) lean = 'over'
  else if (sour) lean = 'under'
  else if (bitter) lean = 'over'
  else lean = 'balanced'

  // Suggestions
  const suggestions = new Map<string, Suggestion>()
  const add = (key: string, title: string, detail: string, priority: number, evidence: string[] = [], grind: number | null = null) => {
    const existing = suggestions.get(key)
    if (existing && existing.priority >= priority) {
      existing.evidence.push(...evidence.filter((e) => !existing.evidence.includes(e)))
      return
    }
    suggestions.set(key, { key, title, detail, priority, evidence, grindTarget: grind })
  }
  const timeEvidence = timeLong
    ? `Shot took ${mmss(input.totalTime)}, ${Math.trunc(timeDelta)} s longer than planned`
    : `Shot took ${mmss(input.totalTime)}, ${Math.trunc(-timeDelta)} s faster than planned`
  const grindSuggestion = (coarser: boolean, priority: number, evidence: string[]) => {
    const direction = coarser ? 'coarser' : 'finer'
    const why = coarser
      ? 'A coarser grind lets the water through faster, so the shot runs quicker and less bitter.'
      : 'A finer grind slows the shot down and extracts more sweetness, so it tastes less sour.'
    const grinder = input.grinder
    if (grinder && grinder.currentValue != null) {
      const value = grinder.currentValue
      const target = bracketed(coarser, value, grinder, input.history) ?? adjustGrind(grinder.spec, value, coarser, timeVeryOff ? 2 : 1)
      add('grind', `Grind ${direction}: ${formatGrind(grinder.spec, target)}`,
        `Go from ${formatGrind(grinder.spec, value)} to ${formatGrind(grinder.spec, target)} on your ${grinder.name}. ${why}`, priority, evidence, target)
    } else if (grinder) {
      add('grind', `Grind ${direction}`, `Adjust your ${grinder.name} a small step ${direction}. Log the setting next time for exact numbers. ${why}`, priority, evidence)
    } else {
      add('grind', `Grind ${direction}`, `Make a small step ${direction}. ${why} Add your grinder in Gear to get exact recommendations.`, priority, evidence)
    }
  }
  const yieldText = (r: number) => `1:${fmt1(r)} (${roundHalfAway(input.dose * r)} g)`
  const ratioEvidence = [`Ratio 1:${fmt1(ratio)}`]

  const channelEvidence: string[] = []
  if (pressure && pressure.suddenDrop >= 2 && pressure.dropTime != null) channelEvidence.push(`Pressure fell ${fmt1(pressure.suddenDrop)} bar at ${mmss(pressure.dropTime)}`)
  if (drops != null && drops < 3) channelEvidence.push(`First drops after ${mmss(drops)}`)
  if (lean === 'uneven' || feedback.has('astringent')) {
    add('puck', 'Improve the puck prep',
      'Break up clumps with a WDT tool, level the bed and tamp straight. A channel lets water rush through one spot: that part over-extracts (bitter, drying) while the rest stays sour.',
      110, channelEvidence)
  }
  if (sour) {
    if (timeShort || pressureLow) grindSuggestion(false, 100, timeShort ? [timeEvidence] : pressure ? [`Peak pressure only ${fmt1(pressure.peak)} bar`] : [])
    else if (ratioLow) add('ratio', `Let it run to ${grams(recipe.water)}`, `You stopped at ${grams(input.finalWeight)}. A longer shot extracts more sweetness and balances the acidity.`, 95, ratioEvidence)
    else add('ratio', `Longer ratio: ${yieldText(Math.max(ratio, targetRatio) + 0.3)}`, 'The shot time was fine, so let it run a few grams longer instead of changing the grind.', 85)
    if (temp < 96) {
      add('temp-up', 'Brew 1–2 °C hotter', `Try ${Math.trunc(temp) + 1}–${Math.trunc(temp) + 2} °C. ${roastIdx != null && roastIdx <= 1 ? 'Light roasts need the heat.' : 'Hotter water extracts more sweetness.'}`,
        75, [`Brewed at ${Math.trunc(temp)} °C`])
    }
  }
  if (bitter) {
    if (timeLong) grindSuggestion(true, 100, [timeEvidence])
    else if (ratioHigh) add('ratio', `Stop at ${grams(recipe.water)}`, `You let it run to ${grams(input.finalWeight)}. The last grams of a shot are the most bitter.`, 95, ratioEvidence)
    else add('ratio', `Shorter ratio: ${yieldText(Math.max(Math.min(ratio, targetRatio) - 0.3, 1))}`, 'The shot time was fine, so stop a few grams earlier instead of changing the grind.', 85)
    add('temp-down', 'Brew 1–2 °C cooler',
      `Try ${Math.trunc(temp) - 2}–${Math.trunc(temp) - 1} °C. ${roastIdx != null && roastIdx >= 3 ? 'Darker roasts extract easily and turn bitter when hot.' : 'Cooler water extracts less of the harsh compounds.'}`,
      75, [`Brewed at ${Math.trunc(temp)} °C`])
  }
  if (feedback.has('weak')) {
    if (ratioHigh) add('strength', `Stop at ${grams(recipe.water)}`, 'More water in the cup means a thinner shot. Stick to the recipe\'s yield.', 90, ratioEvidence)
    else add('strength', `Dose 1 g more (${fmt1(input.dose + 1)} g)`, 'Keep the ratio and use a little more coffee for a stronger, heavier shot. Grind a touch coarser if it then runs slow.', 90)
  }
  if (feedback.has('strong')) {
    add('strength', `Longer ratio: ${yieldText(Math.max(ratio, targetRatio) + 0.3)}`, 'A few more grams in the cup make the shot less intense without changing the grind.', 90)
  }
  if (feedback.has('flat')) {
    if (input.daysOffRoast != null && input.daysOffRoast > 30) {
      add('fresh', 'Use fresher beans', `At ${input.daysOffRoast} days off roast most of the aroma is gone. Espresso is best 7–21 days off roast.`, 85, [`${input.daysOffRoast} days off roast`])
    }
    add('temp-up', 'Brew 1–2 °C hotter', 'A little more heat brings back sweetness and aroma.', 70)
  }
  // Without a taste yet, the shot time alone already says which way to go.
  if (feedback.size === 0) {
    if (timeShort) grindSuggestion(false, 60, [timeEvidence])
    if (timeLong) grindSuggestion(true, 60, [timeEvidence])
  }
  const negative = feedback.size > 0 && !feedback.has('perfect')
  if (negative && input.grinder) {
    const g = input.grinder
    const best = input.history.filter((h) => h.grindValue != null && (h.rating >= 4 || h.feedback.includes('perfect')))
      .reduce<typeof input.history[number] | null>((top, h) => (top == null || h.rating > top.rating ? h : top), null)
    if (best?.grindValue != null && best.grindValue !== g.currentValue) {
      add('history', `Your best shot of this bean: ${formatGrind(g.spec, best.grindValue)}`,
        `On ${formatDate(best.date)} it was rated ${best.rating}★ at ${formatGrind(g.spec, best.grindValue)} (${mmss(best.totalTime)}).`, 66)
    }
  }
  if (feedback.has('perfect')) {
    suggestions.clear()
    const grindText = input.grinder?.currentValue != null ? ` at ${formatGrind(input.grinder.spec, input.grinder.currentValue)}` : ''
    add('repeat', 'Repeat it', `This shot is saved as your reference${grindText}. BrewLog will suggest the same settings next time you use this bean.`, 100)
  }

  const sorted = [...suggestions.values()].sort((a, b) => b.priority - a.priority)
  const suggestedGrind = feedback.has('perfect') ? input.grinder?.currentValue ?? null : sorted.find((s) => s.grindTarget != null)?.grindTarget ?? null

  let headline: string
  if (feedback.size === 0) {
    headline = lean === 'balanced' ? 'The shot went to plan. Now taste it and tell BrewLog how it was.'
      : lean === 'under' ? 'The shot ran fast: watch for sourness.'
        : lean === 'over' ? 'The shot ran slow: watch for bitterness.'
          : lean === 'uneven' ? 'The data hints at channeling. Taste it and tell BrewLog how it was.'
            : 'Taste it and tell BrewLog how it was to get tailored tips.'
  } else if (feedback.has('perfect')) headline = 'Nailed it. These settings are your reference for this coffee.'
  else if (lean === 'uneven') headline = 'Sour and bitter together points to channeling. Start with the puck prep.'
  else if (sour && timeShort) headline = 'Under-extracted: the fast shot explains the sourness.'
  else if (bitter && timeLong) headline = 'Over-extracted: the slow shot explains the bitterness.'
  else headline = "Here's what to change next time, most impactful first."

  return {
    pours: [],
    findings: findings.map((f, i) => ({ f, i })).sort((a, b) => LEVEL_ORDER[b.f.level] - LEVEL_ORDER[a.f.level] || a.i - b.i).map((x) => x.f),
    suggestions: sorted,
    lean,
    headline,
    suggestedGrind,
  }
}
