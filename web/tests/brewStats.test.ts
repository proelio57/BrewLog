import { describe, expect, it } from 'vitest'
import { BrewStats, type StatsEntry, type StatsWeek } from '../src/analysis/brewStats'

describe('BrewStats', () => {
  /** Wednesday, 2026-11-04 12:00 UTC (1_793_793_600 * 1000). */
  const now = 1_793_793_600_000
  const day = 86_400_000

  function entry(options: Partial<StatsEntry> & { daysAgo: number }): StatsEntry {
    const { daysAgo, ...rest } = options
    return {
      date: now - Math.round(daysAgo * day),
      espresso: false,
      rating: 0,
      beanId: null,
      beanName: 'Bean',
      recipeName: 'Recipe',
      dose: 15.0,
      yield: 250.0,
      time: 180.0,
      targetTime: 180.0,
      grind: '',
      ...rest,
    }
  }

  function weeks(ratings: (number | null)[]): StatsWeek[] {
    return ratings.map((r, index) => ({
      start: now + index * 7 * day,
      brews: 1,
      averageRating: r,
    }))
  }

  it('counts weeks and averages ratings correctly', () => {
    const s = BrewStats.summary(
      [
        entry({ daysAgo: 0.0, rating: 4 }),
        entry({ daysAgo: 1.0, rating: 5 }),
        entry({ daysAgo: 2.0, rating: 0 }),
        entry({ daysAgo: 7.0, rating: 3 }),
      ],
      false,
      null,
      now,
    )

    expect(s.weeks).toHaveLength(12)
    expect(s.weeks[s.weeks.length - 1].brews).toBe(3)
    expect(s.weeks[s.weeks.length - 1].averageRating).toBeCloseTo(4.5, 3)
    expect(s.weeks[10].averageRating).toBeCloseTo(3.0, 3)
    expect(s.brews).toBe(4)
    expect(s.averageRating).toBeCloseTo(4.0, 3)
    expect(s.weeks[0].start).toBeLessThan(s.weeks[11].start)
  })

  it('determines rating trend verdicts', () => {
    expect(BrewStats.trend(weeks([3.0, 3.5, 4.0, 4.5]))).toBe('improving')
    expect(BrewStats.trend(weeks([4.0, 4.0, 4.0]))).toBe('steady')
    expect(BrewStats.trend(weeks([5.0, 4.0, 3.0]))).toBe('declining')
    expect(BrewStats.trend(weeks([3.0, null, 5.0]))).toBeNull()
  })

  it('filters by brew kind and date range', () => {
    const entries = [
      entry({ daysAgo: 1.0 }),
      entry({ daysAgo: 2.0, espresso: true, dose: 18.0, yield: 36.0, time: 28.0, targetTime: 28.0 }),
      entry({ daysAgo: 40.0 }),
    ]
    expect(BrewStats.summary(entries, false, null, now).brews).toBe(2)
    expect(BrewStats.summary(entries, true, null, now).brews).toBe(1)
    expect(BrewStats.summary(entries, false, now - 30 * day, now).brews).toBe(1)
  })

  it('computes espresso averages and channeling', () => {
    const entries = [
      entry({
        daysAgo: 1.0,
        espresso: true,
        rating: 4,
        dose: 18.0,
        yield: 36.0,
        time: 28.0,
        firstDrops: 6.0,
        peakPressure: 9.0,
        suddenDrop: 2.5,
      }),
      entry({
        daysAgo: 2.0,
        espresso: true,
        rating: 3,
        dose: 18.0,
        yield: 39.6,
        time: 30.0,
        firstDrops: 2.0,
      }),
      entry({
        daysAgo: 3.0,
        espresso: true,
        rating: 5,
        dose: 18.0,
        yield: 37.8,
        time: 29.0,
      }),
    ]
    const s = BrewStats.summary(entries, true, null, now)
    expect(s.averageRatio).toBeCloseTo(2.1, 3)
    expect(s.averageFirstDrops).toBeCloseTo(4.0, 3)
    expect(s.firstDropsCount).toBe(2)
    expect(s.averagePeakPressure).toBeCloseTo(9.0, 3)
    expect(s.pressureCount).toBe(1)
    expect(s.channelingShots).toBe(2)
    expect(s.points).toHaveLength(3)
    expect(s.averageTime).toBeCloseTo(29.0, 3)
  })

  it('computes pour over time delta and extraction', () => {
    const s = BrewStats.summary(
      [
        entry({ daysAgo: 1.0, time: 192.0, targetTime: 180.0, extractionYield: 20.0 }),
        entry({ daysAgo: 2.0, time: 175.0, targetTime: 180.0 }),
      ],
      false,
      null,
      now,
    )
    expect(s.averageTimeDelta).toBeCloseTo(3.5, 3)
    expect(s.averageExtraction).toBeCloseTo(20.0, 3)
    expect(s.extractionCount).toBe(1)
    expect(s.points).toHaveLength(0)
  })

  it('ranks bean groups by rating when rated >= 2 and identifies best recipe and grind', () => {
    const bean = 'bean-1'
    const s = BrewStats.summary(
      [
        entry({ daysAgo: 1.0, rating: 3, beanId: bean, beanName: 'Kenya', recipeName: 'A', grind: '20' }),
        entry({ daysAgo: 2.0, rating: 5, beanId: bean, beanName: 'Kenya', recipeName: 'B', grind: '22' }),
        entry({ daysAgo: 3.0, rating: 5, beanId: bean, beanName: 'Kenya', recipeName: 'C', grind: '24' }),
      ],
      false,
      null,
      now,
    )
    const group = s.beans[0]
    expect(group).toBeDefined()
    expect(group.name).toBe('Kenya')
    expect(group.brews).toBe(3)
    expect(group.averageRating).toBeCloseTo(13.0 / 3, 3)
    expect(group.bestRecipe).toBe('B')
    expect(group.bestGrind).toBe('22')
    expect(group.lastBrewed).toBe(now - day)
  })

  it('returns empty stats for empty input', () => {
    const s = BrewStats.summary([], false, null, now)
    expect(s.brews).toBe(0)
    expect(s.weeks).toHaveLength(12)
    expect(s.weeks.every((w) => w.brews === 0 && w.averageRating == null)).toBe(true)
    expect(s.trend).toBeNull()
    expect(s.averageRating).toBeNull()
    expect(s.averageRatio).toBeNull()
    expect(s.averageTime).toBeNull()
    expect(s.beans).toHaveLength(0)
    expect(s.recipes).toHaveLength(0)
    expect(s.points).toHaveLength(0)
  })

  it('groups brews without a bean together', () => {
    const s = BrewStats.summary(
      [
        entry({ daysAgo: 1.0, beanId: null, beanName: 'No bean' }),
        entry({ daysAgo: 2.0, beanId: null, beanName: '' }),
      ],
      false,
      null,
      now,
    )
    expect(s.beans).toHaveLength(1)
  })
})
