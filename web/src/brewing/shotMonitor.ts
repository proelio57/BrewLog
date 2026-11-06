export type ShotAction = 'none' | 'stop' | 'finish'

export interface ShotReading {
  t: number
  grams: number
}

/**
 * Decides during an espresso shot when to stop (just before the target yield, so the last drips land on it) and
 * when the shot is over (the weight has settled near the yield), and keeps the live numbers.
 * Port of ShotMonitor.swift / ShotMonitor.kt.
 */
export class ShotMonitor {
  static readonly SETTLE_WINDOW = 1.5
  static readonly SETTLE_TOLERANCE = 0.3
  static readonly SETTLE_MINIMUM_READINGS = 4
  static readonly FINISH_SHARE = 0.9

  firstDropsTime: number | null = null
  stopped = false
  finished = false
  private lastGrams = 0
  private recent: ShotReading[] = []

  constructor(
    readonly yieldTarget: number,
    readonly dose: number,
    readonly stopLag = 1.0,
    readonly autoStop = true,
  ) {}

  /** The ratio so far (grams in the cup per gram of coffee), null before the first gram or without a dose. */
  get liveRatio(): number | null {
    if (this.dose <= 0 || this.lastGrams < 1.0) return null
    return this.lastGrams / this.dose
  }

  ingest(grams: number, flow: number, t: number): ShotAction {
    if (!Number.isFinite(grams) || !Number.isFinite(t)) return 'none'
    this.lastGrams = grams
    if (this.firstDropsTime == null && grams >= 1.0) {
      this.firstDropsTime = t
    }
    this.recent.push({ t, grams })
    this.recent = this.recent.filter((r) => t - r.t <= ShotMonitor.SETTLE_WINDOW)

    if (this.autoStop && this.yieldTarget > 0 && !this.stopped && ShotMonitor.shouldStop(grams, flow, this.yieldTarget, this.stopLag)) {
      this.stopped = true
      return 'stop'
    }
    if (
      this.yieldTarget > 0 &&
      !this.finished &&
      grams >= this.yieldTarget * ShotMonitor.FINISH_SHARE &&
      ShotMonitor.isSettled(this.recent, t)
    ) {
      this.finished = true
      return 'finish'
    }
    return 'none'
  }

  /**
   * Stop when the weight plus what is still on its way (flow * lag) reaches the yield. A negative flow (cup
   * bumped, scale noise) counts as none.
   */
  static shouldStop(weight: number, flow: number, yieldTarget: number, lag: number): boolean {
    return weight + Math.max(flow, 0) * Math.max(lag, 0) >= yieldTarget
  }

  /** Enough recent readings, all close together: nothing is dripping any more. */
  static isSettled(readings: ShotReading[], now: number): boolean {
    const window = readings.filter((r) => now - r.t <= ShotMonitor.SETTLE_WINDOW).map((r) => r.grams)
    if (window.length < ShotMonitor.SETTLE_MINIMUM_READINGS) return false
    const low = Math.min(...window)
    const high = Math.max(...window)
    return high - low <= 2 * ShotMonitor.SETTLE_TOLERANCE
  }

  /**
   * The brew temperature to save: machine target wins (the machine's settings are always right), then the
   * measured average, then the recipe. Implausible values (outside 70-105 °C) are skipped.
   */
  static shotTemperature(recipe: number, machineTarget?: number | null, measuredAverage?: number | null): number {
    for (const val of [machineTarget, measuredAverage]) {
      if (val != null && Number.isFinite(val) && val >= 70 && val <= 105) return val
    }
    return recipe
  }

  /** The pressure the shot is judged against: machine target (1-15 bar) wins over the recipe's. */
  static targetPressure(recipe?: number | null, machineTarget?: number | null): number | null {
    if (machineTarget != null && Number.isFinite(machineTarget) && machineTarget >= 1.0 && machineTarget <= 15.0) {
      return machineTarget
    }
    return recipe ?? null
  }
}
