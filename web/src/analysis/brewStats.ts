import { grindDisplay, type Brew, type MachineSample, type WeightSample } from '../domain/models'
import { Extraction } from '../domain/extraction'
import { firstDrops, pressureSummary } from './espresso'

export interface StatsEntry {
  date: number
  espresso: boolean
  /** 0 = not rated; never counts toward averages. */
  rating: number
  beanId: string | null
  beanName: string
  recipeName: string
  dose: number
  yield: number
  time: number
  targetTime: number
  grind: string
  extractionYield?: number | null
  firstDrops?: number | null
  peakPressure?: number | null
  suddenDrop?: number | null
}

export interface StatsWeek {
  start: number
  brews: number
  averageRating: number | null
}

export type StatsTrend = 'improving' | 'steady' | 'declining'

export interface StatsGroup {
  id: string
  name: string
  brews: number
  averageRating: number | null
  bestRecipe: string | null
  bestGrind: string | null
  lastBrewed: number
}

export interface StatsPoint {
  time: number
  ratio: number
  rating: number
}

export interface StatsSummary {
  brews: number
  weeks: StatsWeek[]
  trend: StatsTrend | null
  averageRating: number | null
  averageRatio: number | null
  averageTime: number | null
  /** Pour-over: average of brew time minus target time (positive = slower than the recipe). */
  averageTimeDelta: number | null
  averageExtraction: number | null
  extractionCount: number
  averageFirstDrops: number | null
  firstDropsCount: number
  averagePeakPressure: number | null
  pressureCount: number
  channelingShots: number
  beans: StatsGroup[]
  recipes: StatsGroup[]
  points: StatsPoint[]
}

export const BrewStats = {
  WEEK_COUNT: 12,
  TREND_THRESHOLD: 0.05,
  CHANNELING_DROP: 2.0,
  CHANNELING_FIRST_DROPS: 3.0,
  NO_BEAN_NAME: 'No bean',

  summary(
    entries: StatsEntry[],
    espresso = false,
    since: number | null = null,
    now: number = Date.now(),
  ): StatsSummary {
    const selected = entries.filter((entry) => {
      if (entry.espresso !== espresso) return false
      if (since != null && entry.date < since) return false
      return true
    })

    const weeks = BrewStats.weeks(selected, now)

    const ratios = selected.filter((it) => it.dose > 0 && it.yield > 0).map((it) => it.yield / it.dose)
    const timed = selected.filter((it) => it.time > 0)
    const times = timed.map((it) => it.time)
    const deltas = timed.filter((it) => it.targetTime > 0).map((it) => it.time - it.targetTime)
    const extractions = selected
      .map((it) => it.extractionYield)
      .filter((it): it is number => it != null && Number.isFinite(it))
    const firstDrops = selected
      .map((it) => it.firstDrops)
      .filter((it): it is number => it != null && Number.isFinite(it))
    const peaks = selected
      .map((it) => it.peakPressure)
      .filter((it): it is number => it != null && Number.isFinite(it))

    const beans = BrewStats.groups(selected, (entry) => {
      const id = entry.beanId ?? 'no-bean'
      const name = entry.beanName.trim().length === 0 ? BrewStats.NO_BEAN_NAME : entry.beanName
      return [id, name]
    })

    const recipes = BrewStats.groups(selected, (entry) => [entry.recipeName, entry.recipeName])

    const channeling = espresso ? selected.filter((it) => BrewStats.showsChanneling(it)).length : 0

    const points: StatsPoint[] = espresso
      ? selected
          .filter((entry) => entry.time > 0 && entry.dose > 0 && entry.yield > 0)
          .map((entry) => ({
            time: entry.time,
            ratio: entry.yield / entry.dose,
            rating: entry.rating,
          }))
      : []

    const ratedBrews = selected.filter((it) => it.rating > 0).map((it) => it.rating)

    return {
      brews: selected.length,
      weeks,
      trend: BrewStats.trend(weeks),
      averageRating: BrewStats.average(ratedBrews),
      averageRatio: BrewStats.average(ratios),
      averageTime: BrewStats.average(times),
      averageTimeDelta: espresso ? null : BrewStats.average(deltas),
      averageExtraction: BrewStats.average(extractions),
      extractionCount: extractions.length,
      averageFirstDrops: BrewStats.average(firstDrops),
      firstDropsCount: firstDrops.length,
      averagePeakPressure: BrewStats.average(peaks),
      pressureCount: peaks.length,
      channelingShots: channeling,
      beans,
      recipes,
      points,
    }
  },

  showsChanneling(entry: StatsEntry): boolean {
    if (entry.suddenDrop != null && entry.suddenDrop >= BrewStats.CHANNELING_DROP) return true
    if (entry.firstDrops != null && entry.firstDrops < BrewStats.CHANNELING_FIRST_DROPS) return true
    return false
  },

  trend(weeks: StatsWeek[]): StatsTrend | null {
    const xs: number[] = []
    const ys: number[] = []
    for (let i = 0; i < weeks.length; i++) {
      const rating = weeks[i].averageRating
      if (rating != null) {
        xs.push(i)
        ys.push(rating)
      }
    }
    if (xs.length < 3) return null

    const n = xs.length
    const meanX = xs.reduce((a, b) => a + b, 0) / n
    const meanY = ys.reduce((a, b) => a + b, 0) / n
    let sxx = 0
    let sxy = 0
    for (let i = 0; i < n; i++) {
      const dx = xs[i] - meanX
      const dy = ys[i] - meanY
      sxx += dx * dx
      sxy += dx * dy
    }
    if (sxx <= 0) return null
    const slope = sxy / sxx
    if (slope > BrewStats.TREND_THRESHOLD) return 'improving'
    if (slope < -BrewStats.TREND_THRESHOLD) return 'declining'
    return 'steady'
  },

  weeks(entries: StatsEntry[], now: number): StatsWeek[] {
    const d = new Date(now)
    const day = d.getUTCDay()
    const diffToMonday = (day + 6) % 7
    const thisWeekMonday = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - diffToMonday, 0, 0, 0, 0))
    const thisWeekStart = thisWeekMonday.getTime()

    const starts: number[] = []
    for (let offset = BrewStats.WEEK_COUNT - 1; offset >= 0; offset--) {
      starts.push(thisWeekStart - offset * 7 * 86_400_000)
    }

    const buckets: StatsEntry[][] = Array.from({ length: BrewStats.WEEK_COUNT }, () => [])
    for (const entry of entries) {
      if (entry.date < starts[0]) continue
      let index = -1
      for (let i = starts.length - 1; i >= 0; i--) {
        if (entry.date >= starts[i]) {
          index = i
          break
        }
      }
      if (index < 0) index = BrewStats.WEEK_COUNT - 1
      buckets[index].push(entry)
    }

    return starts.map((start, idx) => {
      const brews = buckets[idx]
      const ratings = brews.filter((b) => b.rating > 0).map((b) => b.rating)
      return {
        start,
        brews: brews.length,
        averageRating: BrewStats.average(ratings),
      }
    })
  },

  groups(entries: StatsEntry[], key: (entry: StatsEntry) => [string, string]): StatsGroup[] {
    const byId = new Map<string, { name: string; entries: StatsEntry[] }>()
    for (const entry of entries) {
      const [id, name] = key(entry)
      let group = byId.get(id)
      if (!group) {
        group = { name, entries: [] }
        byId.set(id, group)
      }
      group.entries.push(entry)
    }

    const ranked: { group: StatsGroup; ratedCount: number }[] = []
    for (const [id, { name, entries: groupEntries }] of byId.entries()) {
      const rated = groupEntries.filter((it) => it.rating > 0)
      let best: StatsEntry | null = null
      for (const item of rated) {
        if (!best) best = item
        else if (item.rating > best.rating || (item.rating === best.rating && item.date > best.date)) {
          best = item
        }
      }

      const grind = best?.grind ? best.grind : null
      const last = groupEntries.reduce((max, it) => Math.max(max, it.date), 0)
      const group: StatsGroup = {
        id,
        name,
        brews: groupEntries.length,
        averageRating: BrewStats.average(rated.map((it) => it.rating)),
        bestRecipe: best?.recipeName ?? null,
        bestGrind: grind,
        lastBrewed: last,
      }
      ranked.push({ group, ratedCount: rated.length })
    }

    ranked.sort((a, b) => {
      const aRanked = a.ratedCount >= 2
      const bRanked = b.ratedCount >= 2
      if (aRanked !== bRanked) return aRanked ? -1 : 1
      if (aRanked && a.group.averageRating !== b.group.averageRating) {
        return (b.group.averageRating ?? 0) - (a.group.averageRating ?? 0)
      }
      if (a.group.brews !== b.group.brews) {
        return b.group.brews - a.group.brews
      }
      return b.group.lastBrewed - a.group.lastBrewed
    })

    return ranked.map((r) => r.group)
  },

  average(values: number[]): number | null {
    if (values.length === 0) return null
    return values.reduce((a, b) => a + b, 0) / values.length
  },

  signedSeconds(delta: number): string {
    const seconds = Math.round(delta)
    if (seconds === 0) return 'on time'
    return seconds > 0 ? `+${seconds} s` : `−${-seconds} s`
  },

  fromBrew(
    brew: Brew,
    beanName = '',
    samples: WeightSample[] | null = null,
    machineSamples: MachineSample[] | null = null,
  ): StatsEntry {
    const isEsp = brew.recipe?.method === 'espresso'
    const pressure = isEsp && machineSamples && machineSamples.length > 0 ? pressureSummary(machineSamples) : null
    const drops = isEsp && samples && samples.length > 0 ? firstDrops(samples) : null
    const ey = brew.tds != null && brew.tds > 0 ? Extraction.yield(brew.tds, brew.drinkWeight ?? brew.finalWeight, brew.dose) : null

    return {
      date: brew.date,
      espresso: isEsp,
      rating: brew.rating,
      beanId: brew.beanId,
      beanName: beanName || brew.notes || BrewStats.NO_BEAN_NAME,
      recipeName: brew.recipeName || brew.recipe?.name || '',
      dose: brew.dose,
      yield: brew.finalWeight,
      time: brew.totalTime,
      targetTime: brew.recipe?.targetTime ?? 0,
      grind: grindDisplay(brew),
      extractionYield: ey,
      firstDrops: drops,
      peakPressure: pressure?.peak ?? null,
      suddenDrop: pressure?.suddenDrop ?? null,
    }
  },
}
