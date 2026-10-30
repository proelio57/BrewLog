import { Store } from '../data/store'
import { roundHalfAway } from '../domain/format'
import type { AppSettings, MachineSample, WeightSample } from '../domain/models'
import { isPour, type Recipe } from '../domain/recipe'
import { LIMITS } from '../domain/validation'
import { acceptedDose, doseStatus, recipeForDose, stableWeight, type DoseStatus } from './dosing'
import { type GaggiMateStatus, hasWeight, isBrewing } from '../machine/gaggimate'
import type { MachineManager } from '../machine/machineManager'
import type { PressureMonitor } from '../scale/pressure'
import { type ScaleCommands, monotonicMillis } from '../scale/scaleManager'

// 1:1 port of BrewSession.swift / BrewSession.kt.

export type BrewCue = 'target' | 'nextStep' | 'finish' | 'tick'
export type BrewPhase = 'dosing' | 'preparing' | 'armed' | 'brewing' | 'finished'

/** Immutable snapshot of the live brew for the UI. */
export interface BrewSnapshot {
  phase: BrewPhase
  usesScale: boolean
  elapsed: number
  weight: number
  flowRate: number
  samples: WeightSample[]
  zeroConfirmed: boolean
  currentStepIndex: number | null
  nextStepIndex: number | null
  timeToNextStep: number | null
  countdownProgress: number
  activeTarget: number | null
  activePourBase: number
  overpour: number | null
  pingLead: number
  flash: BrewCue | null
  /** Espresso: pressure/temperature/flow recorded during the shot. */
  machineSamples: MachineSample[]
  /** The bean dose read from the scale, null when the beans weren't weighed. */
  weighedDose: number | null
  doseStatus: DoseStatus
}

/** Hard limits so a forgotten brew or a misbehaving device can't grow memory without bound. */
export const MAX_RECENT_READINGS = 120
export const MAX_SAMPLES = LIMITS.maxBrewSeconds * 10 + 10

/** Least-squares slope (g/s) over the last `window` seconds. */
export function slope(readings: readonly (readonly [number, number])[], window: number, nowMs: number): number {
  const points = readings.filter(([t]) => (nowMs - t) / 1000 <= window)
  if (points.length < 3) return 0
  const t0 = points[0][0]
  const xs = points.map(([t]) => (t - t0) / 1000)
  const ys = points.map(([, w]) => w)
  const meanX = xs.reduce((a, b) => a + b, 0) / xs.length
  const meanY = ys.reduce((a, b) => a + b, 0) / ys.length
  let numerator = 0
  let denominator = 0
  xs.forEach((x, i) => {
    numerator += (x - meanX) * (ys[i] - meanY)
    denominator += (x - meanX) * (x - meanX)
  })
  return denominator > 0.0001 ? numerator / denominator : 0
}

/** Drives a live brew: auto-start on first pour, step timing, buffered target pings, countdowns and recording. */
export class BrewSession {
  usesScale: boolean
  phase: BrewPhase = 'preparing'
  elapsed = 0
  /** Called when a brew runs past the maximum duration (e.g. the user walked away). */
  onAutoFinish: (() => void) | null = null

  private weight = 0
  private flowRate = 0
  private samples: WeightSample[] = []
  private maxWeight = 0
  private targetPinged = new Set<number>()
  private startPinged = new Set<number>()
  private zeroConfirmed = false
  private startMs: number | null = null
  private armMs: number | null = null
  private recent: [number, number][] = []
  private lastSampleT = -1
  private retareSent = false
  private finishPinged = false
  private lastTickSecond: number | null = null
  private flash: BrewCue | null = null
  private flashUntil = 0
  private readonly pourIndices: number[]
  private machineSamples: MachineSample[] = []
  private lastMachineSampleT = -1
  /** The weight comes from the scale connected to the espresso machine instead of BrewLog's own connection. */
  private weighsViaMachine = false
  private weighedDose: number | null = null
  private dosePinged = false
  private prepared = false
  readonly state: Store<BrewSnapshot>

  /** The recipe brewed: the planned one, or scaled to the weighed dose when that is at least 0.5 g off. */
  recipe: Recipe
  /** The last settled reading while weighing; "Ready" keeps it even after the cup is lifted off. */
  private settledDose: number | null = null

  constructor(
    /** The recipe as planned (scaled to the dose chosen on the Brew tab). */
    readonly plannedRecipe: Recipe,
    private readonly scale: ScaleCommands,
    private readonly settings: () => AppSettings,
    private readonly onCue: (cue: BrewCue) => void,
    private readonly clock: () => number = monotonicMillis,
    private readonly machine: MachineManager | null = null,
    private readonly monitor: PressureMonitor | null = null,
  ) {
    this.recipe = plannedRecipe
    this.usesScale = scale.isReady || (this.isEspresso && !!machine?.isConnected && hasWeight(machine.status))
    this.pourIndices = plannedRecipe.steps.map((s, i) => (isPour(s.kind) && s.target != null ? i : -1)).filter((i) => i >= 0)
    this.state = new Store(this.snapshot())
  }

  /** Water poured: the max weight seen, so lifting the dripper at the end doesn't distort it. */
  get finalWeight(): number {
    return this.usesScale ? this.maxWeight : this.recipe.water
  }

  recordedSamples(): WeightSample[] {
    return [...this.samples]
  }

  recordedMachineSamples(): MachineSample[] {
    return [...this.machineSamples]
  }

  get isEspresso(): boolean {
    return this.recipe.method === 'espresso'
  }

  /** Espresso with a connected machine: the shot timer starts and stops with the machine's pump. */
  get followsMachine(): boolean {
    return this.isEspresso && !!this.machine?.isConnected
  }

  /** Espresso with live pressure, from the BOOKOO Espresso Monitor or the machine. */
  get hasPressure(): boolean {
    return this.isEspresso && (!!this.monitor?.isReady || (!!this.machine?.isConnected && this.machine.status.hasPressure !== false))
  }

  /** Listens to the machine and the pressure sensor (espresso only). Returns the cleanup. */
  attach(): () => void {
    if (!this.isEspresso) return () => undefined
    const cleanups = [
      this.machine?.onShot((started, at) => this.machineShot(started, at)),
      this.machine?.onReading((status, at) => this.machineReading(status, at)),
      this.monitor?.onPressure((bar, at) => this.monitorReading(bar, at)),
    ]
    return () => cleanups.forEach((cleanup) => cleanup?.())
  }

  /** The planned bean dose (the recipe is already scaled to it). */
  get plannedDose(): number {
    return this.plannedRecipe.dose
  }

  /** The dose to save with the brew. */
  get dose(): number {
    return this.weighedDose ?? this.plannedDose
  }

  /** Weighing the beans needs BrewLog's own scale. */
  get canWeighBeans(): boolean {
    return this.scale.isReady && (this.phase === 'preparing' || this.phase === 'dosing')
  }

  /** Called once when the live screen opens: starts by weighing the beans if that's switched on. */
  prepare(): void {
    // Only once per brew, so re-mounting the screen doesn't ask again.
    if (this.prepared) return
    this.prepared = true
    if (this.settings().weighBeansFirst) this.weighBeans()
  }

  /** Tare the scale and weigh the beans against the planned dose. */
  weighBeans(): void {
    if (!this.scale.isReady || this.phase !== 'preparing') return
    this.phase = 'dosing'
    this.dosePinged = false
    this.settledDose = null
    this.scale.prepareForDosing(this.plannedDose)
    this.publish()
  }

  /** Tare while weighing (e.g. after putting the cup on the scale). */
  tareDose(): void {
    if (this.phase !== 'dosing') return
    this.scale.tare()
    this.settledDose = null
    this.dosePinged = false
    this.recent = []
    this.publish()
  }

  /** Ends weighing: keeps the settled (or current) reading and scales the recipe from 0.5 g off. Nothing weighed: the plan stays. */
  private finishDosing(): void {
    if (this.phase !== 'dosing') return
    const reading = this.settledDose ?? (doseStatus(this.weight, this.plannedDose) === 'empty' ? null : this.weight)
    if (reading != null) {
      const dose = acceptedDose(reading, this.plannedDose)
      this.weighedDose = dose
      this.recipe = recipeForDose(this.plannedRecipe, dose)
    }
    this.scale.dosingFinished()
    this.phase = 'preparing'
  }

  /** Optional: brew with the planned dose without weighing. */
  skipDosing(): void {
    if (this.phase !== 'dosing') return
    this.scale.dosingFinished()
    this.phase = 'preparing'
    this.publish()
  }

  /** "Ready": tare the scale and wait for the first pour. While weighing it keeps the weighed dose first. */
  ready(): void {
    this.finishDosing()
    this.weighsViaMachine = !this.scale.isReady && this.isEspresso && !!this.machine?.isConnected && hasWeight(this.machine.status)
    this.usesScale = this.scale.isReady || this.weighsViaMachine
    this.phase = 'armed'
    this.armMs = this.clock()
    this.zeroConfirmed = false
    this.retareSent = false
    this.recent = []
    if (this.weighsViaMachine) this.machine?.tareScale()
    else if (this.usesScale) this.scale.prepareForBrew(this.recipe)
    if (this.followsMachine) this.machine?.prepareForShot(this.recipe)
    if (this.isEspresso) this.monitor?.prepareForShot(this.recipe)
    this.publish()
  }

  /** Espresso: starts the shot on the machine if it can be controlled, otherwise just the timer. */
  startShot(): void {
    if (this.followsMachine) this.machine?.startShot()
    else this.startManually()
  }

  private machineShot(started: boolean, atMs: number): void {
    if (started) {
      if (this.phase === 'preparing' || this.phase === 'dosing') {
        this.ready()
        this.begin(atMs)
      } else if (this.phase === 'armed') {
        this.begin(atMs)
      }
    } else if (this.phase === 'brewing') {
      // The pump stopped. Give the last drops a few seconds, then finish.
      setTimeout(() => { if (this.phase === 'brewing') this.onAutoFinish?.() }, 3_000)
    }
  }

  private machineReading(status: GaggiMateStatus, atMs: number): void {
    if (this.weighsViaMachine && status.weight != null) this.ingest(status.weight, atMs)
    // With the pressure sensor connected, its (faster, group-head) readings make the curve.
    if (this.monitor?.isReady) return
    this.recordPressure(status.pressure ?? 0, status.temperature, status.flow, atMs)
  }

  private monitorReading(bar: number, atMs: number): void {
    // Without a machine connection, rising pressure means the pump started: start the shot timer.
    if (this.phase === 'armed' && !this.followsMachine && bar >= 1) this.begin(atMs)
    const status = this.machine?.isConnected ? this.machine.status : null
    this.recordPressure(bar, status?.temperature ?? null, status?.flow ?? null, atMs)
  }

  private recordPressure(bar: number, temperature: number | null, flow: number | null, atMs: number): void {
    if (this.phase !== 'brewing' || this.startMs == null || this.machineSamples.length >= MAX_SAMPLES) return
    const t = (atMs - this.startMs) / 1000
    if (t - this.lastMachineSampleT < 0.2) return
    this.lastMachineSampleT = t
    this.machineSamples.push({
      t: roundHalfAway(t * 100) / 100, p: roundHalfAway(bar * 100) / 100,
      c: temperature != null ? roundHalfAway(temperature * 10) / 10 : null, f: flow != null ? roundHalfAway(flow * 100) / 100 : null,
    })
  }

  startManually(): void {
    this.begin(this.clock())
  }

  finish(): void {
    if (this.phase !== 'brewing' || this.startMs == null) return
    this.elapsed = (this.clock() - this.startMs) / 1000
    this.phase = 'finished'
    if (this.usesScale) {
      this.appendSample(this.elapsed, this.weight, true)
      if (!this.weighsViaMachine) this.scale.brewFinished()
    }
    // Ending the brew by hand also stops the pump if the machine is still pulling the shot.
    if (this.followsMachine && this.machine && isBrewing(this.machine.status)) this.machine.stopShot()
    this.monitor?.shotFinished()
    this.publish()
  }

  /** Brew discarded mid-way: stop the scale timer / demo simulation too. */
  discard(): void {
    if (this.phase === 'dosing') this.scale.dosingFinished()
    if (this.usesScale && !this.weighsViaMachine && (this.phase === 'armed' || this.phase === 'brewing')) this.scale.brewFinished()
    if (this.isEspresso) {
      this.machine?.cancelShot()
      this.monitor?.shotFinished()
    }
  }

  ingest(grams: number, atMs: number): void {
    if (!Number.isFinite(grams)) return
    this.weight = grams
    this.recent.push([atMs, grams])
    while (this.recent.length && atMs - this.recent[0][0] > 3_000) this.recent.shift()
    while (this.recent.length > MAX_RECENT_READINGS) this.recent.shift()
    this.flowRate = slope(this.recent, 1.2, atMs)

    if (this.phase === 'dosing') {
      const settled = stableWeight(this.recent, atMs)
      if (settled != null) this.settledDose = settled
      // One ping when the dose is reached, so you can stop adding beans without staring at the number.
      if (!this.dosePinged && doseStatus(grams, this.plannedDose) === 'onTarget') {
        this.dosePinged = true
        this.onCue('target')
      }
    } else if (this.phase === 'armed') {
      if (!this.usesScale || this.armMs == null) return
      if (!this.zeroConfirmed) {
        if (Math.abs(grams) < 1 && atMs - this.armMs > 250) {
          this.zeroConfirmed = true
        } else if (atMs - this.armMs > 3_000 && !this.retareSent) {
          if (this.weighsViaMachine) this.machine?.tareScale()
          else this.scale.tare()
          this.retareSent = true
        }
      } else if (grams >= this.settings().autoStartThreshold && !this.followsMachine) {
        // Backdate the start to when the weight first left zero.
        let onset = atMs
        for (let i = this.recent.length - 1; i >= 0; i--) {
          if (this.recent[i][1] > 0.3) onset = this.recent[i][0]
          else break
        }
        this.begin(onset)
      }
    } else if (this.phase === 'brewing' && this.startMs != null) {
      this.maxWeight = Math.max(this.maxWeight, grams)
      this.appendSample((atMs - this.startMs) / 1000, grams, false)
      this.checkTargetPing()
    }
  }

  tick(): void {
    const now = this.clock()
    if (this.flash && now >= this.flashUntil) this.flash = null
    if (this.phase === 'brewing' && this.startMs != null) {
      this.elapsed = (now - this.startMs) / 1000
      if (this.elapsed >= LIMITS.maxBrewSeconds) {
        this.onAutoFinish?.()
        return
      }
      this.checkStepStarts()
      this.checkCountdownTicks()
      this.checkFinishPing()
    }
    this.publish()
  }

  private begin(atMs: number): void {
    this.startMs = atMs
    this.elapsed = Math.max((this.clock() - atMs) / 1000, 0)
    this.phase = 'brewing'
    this.samples = [{ t: 0, w: 0 }]
    this.lastSampleT = 0
    this.machineSamples = []
    this.lastMachineSampleT = -1
    if (this.usesScale && !this.weighsViaMachine) this.scale.brewStarted()
    // The first step at 0:00 is silent; just mark it as started.
    this.recipe.steps.forEach((step, index) => {
      if (step.time <= 0) this.startPinged.add(index)
    })
    this.publish()
  }

  private checkStepStarts(): void {
    this.recipe.steps.forEach((step, index) => {
      if (step.time > 0 && step.time <= this.elapsed && !this.startPinged.has(index)) {
        this.startPinged.add(index)
        // Don't replay cues that were missed (e.g. tab was in the background)
        if (this.elapsed - step.time < 2) this.fire('nextStep')
      }
    })
  }

  private checkCountdownTicks(): void {
    if (!this.settings().countdownTicks) return
    const remaining = this.timeToNextStep()
    if (remaining == null) return
    const second = Math.ceil(remaining)
    if (second >= 1 && second <= 3 && second !== this.lastTickSecond && remaining < second) {
      this.lastTickSecond = second
      if (second - remaining < 0.2) this.onCue('tick')
    }
  }

  private checkFinishPing(): void {
    if (this.finishPinged || !this.settings().finishPing || this.elapsed < this.recipe.targetTime) return
    this.finishPinged = true
    // Skip if a recipe step already chimes at this moment (e.g. "remove dripper")
    if (this.recipe.steps.some((s) => Math.abs(s.time - this.recipe.targetTime) < 1.5)) return
    if (this.elapsed - this.recipe.targetTime < 2) this.fire('finish')
  }

  private checkTargetPing(): void {
    const index = this.activePourIndex()
    if (index == null) return
    const target = this.recipe.steps[index].target
    if (target == null || this.targetPinged.has(index)) return
    if (this.weight >= target - this.pingLead()) {
      this.targetPinged.add(index)
      this.fire('target')
    }
  }

  private fire(cue: BrewCue): void {
    this.onCue(cue)
    this.flash = cue
    this.flashUntil = this.clock() + 800
  }

  private appendSample(t: number, grams: number, force: boolean): void {
    if (!force && t - this.lastSampleT < 0.1) return
    if (this.samples.length >= MAX_SAMPLES) return
    this.lastSampleT = t
    this.samples.push({ t: roundHalfAway(t * 100) / 100, w: roundHalfAway(grams * 10) / 10 })
  }

  // Derived state

  private currentStepIndex(): number | null {
    for (let i = this.recipe.steps.length - 1; i >= 0; i--) if (this.recipe.steps[i].time <= this.elapsed) return i
    return null
  }

  private nextStepIndex(): number | null {
    const index = this.recipe.steps.findIndex((s) => s.time > this.elapsed)
    return index >= 0 ? index : null
  }

  private timeToNextStep(): number | null {
    if (this.phase !== 'brewing') return null
    const next = this.nextStepIndex()
    return next == null ? null : this.recipe.steps[next].time - this.elapsed
  }

  private countdownProgress(): number {
    if (this.phase !== 'brewing') return 0
    const current = this.currentStepIndex()
    const next = this.nextStepIndex()
    const previous = current != null ? this.recipe.steps[current].time : 0
    const nextTime = next != null ? this.recipe.steps[next].time : this.recipe.targetTime
    const span = Math.max(nextTime - previous, 1)
    return Math.min(Math.max((this.elapsed - previous) / span, 0), 1)
  }

  /** The pour the user should be doing right now (allows starting up to 3 s early). */
  private activePourIndex(): number | null {
    if (!this.pourIndices.length) return null
    const t = this.phase === 'brewing' ? this.elapsed : 0
    let active: number | null = null
    for (const i of this.pourIndices) if (this.recipe.steps[i].time <= t) active = i
    const next = this.pourIndices.find((i) => this.recipe.steps[i].time > t)
    if (next != null && this.recipe.steps[next].time - t <= 3 && (active == null || this.targetPinged.has(active))) active = next
    return active ?? this.pourIndices[0]
  }

  private activePourBase(): number {
    const active = this.activePourIndex()
    if (active == null) return 0
    const position = this.pourIndices.indexOf(active)
    return position > 0 ? this.recipe.steps[this.pourIndices[position - 1]].target ?? 0 : 0
  }

  private overpour(): number | null {
    if (!this.usesScale) return null
    const active = this.activePourIndex()
    const target = active != null ? this.recipe.steps[active].target : null
    if (target == null) return null
    const over = this.weight - target
    return over > Math.max(2, target * 0.02) ? over : null
  }

  /** The current ping buffer in grams. */
  pingLead(): number {
    const s = this.settings()
    if (s.pingLeadMode === 'fixed') return Math.max(s.pingLeadGrams, 0)
    // Water in the air + scale latency + human reaction time ≈ flow × reaction time.
    return Math.min(Math.max(Math.max(this.flowRate, 0) * s.reactionTime + 1, 1.5), 10)
  }

  private snapshot(): BrewSnapshot {
    const active = this.activePourIndex()
    return {
      phase: this.phase,
      usesScale: this.usesScale,
      elapsed: this.elapsed,
      weight: this.weight,
      flowRate: this.flowRate,
      samples: this.samples.slice(),
      zeroConfirmed: this.zeroConfirmed,
      currentStepIndex: this.currentStepIndex(),
      nextStepIndex: this.nextStepIndex(),
      timeToNextStep: this.timeToNextStep(),
      countdownProgress: this.countdownProgress(),
      activeTarget: active != null ? this.recipe.steps[active].target ?? null : null,
      activePourBase: this.activePourBase(),
      overpour: this.overpour(),
      pingLead: this.pingLead(),
      flash: this.flash,
      machineSamples: this.machineSamples.slice(),
      weighedDose: this.weighedDose,
      doseStatus: doseStatus(this.weight, this.plannedDose),
    }
  }

  private publish(): void {
    this.state.set(this.snapshot())
  }
}
