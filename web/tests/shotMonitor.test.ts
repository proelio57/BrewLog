import { describe, expect, it } from 'vitest'
import { ShotMonitor, type ShotAction } from '../src/brewing/shotMonitor'

describe('ShotMonitor', () => {
  it('stops ahead of the yield', () => {
    expect(ShotMonitor.shouldStop(34.2, 2.0, 36.0, 1.0)).toBe(true) // 36.2 >= 36
    expect(ShotMonitor.shouldStop(33.5, 2.0, 36.0, 1.0)).toBe(false) // 35.5 < 36
  })

  it('stops once and ignores negative flow', () => {
    const m = new ShotMonitor(36.0, 18.0, 1.0, true)
    expect(m.ingest(35.9, -5.0, 20.0)).toBe('none') // bump: negative flow counts as 0
    expect(m.ingest(36.0, 1.5, 20.1)).toBe('stop')
    expect(m.ingest(37.0, 1.5, 20.2)).toBe('none') // only once
  })

  it('finishes when settled after ninety percent', () => {
    const m = new ShotMonitor(36.0, 18.0, 1.0, false)
    const actions: ShotAction[] = []
    for (let i = 0; i < 8; i++) {
      const weight = 33.0 + (i % 2 === 0 ? 0.1 : 0.0)
      actions.push(m.ingest(weight, 0.0, 30.0 + i * 0.2))
    }
    // 33 g >= 32.4 (90 %), settled within +/- 0.3 g after 4 readings — and only once.
    expect(actions.filter((a) => a === 'finish')).toHaveLength(1)
    expect(actions.indexOf('finish')).toBe(3)
  })

  it('is not finished below ninety percent', () => {
    const m = new ShotMonitor(36.0, 18.0, 1.0, false)
    for (let i = 0; i < 10; i++) {
      expect(m.ingest(20.0, 0.0, i * 0.2)).toBe('none')
    }
  })

  it('records first drops and live ratio', () => {
    const m = new ShotMonitor(36.0, 18.0, 1.0, true)
    m.ingest(0.4, 0.2, 5.0)
    m.ingest(1.2, 0.8, 6.5)
    expect(m.firstDropsTime).toBeCloseTo(6.5, 4)
    expect(m.liveRatio).toBeCloseTo(1.2 / 18.0, 4)
  })

  it('does not stop when no yield target is set', () => {
    const m = new ShotMonitor(0.0, 0.0, 1.0, true)
    expect(m.ingest(50.0, 3.0, 10.0)).toBe('none')
    expect(m.liveRatio).toBeNull()
  })

  it('prioritizes machine target temperature and pressure', () => {
    expect(ShotMonitor.shotTemperature(93.0, 91.0, 90.4)).toBe(91.0)
    expect(ShotMonitor.shotTemperature(93.0, null, 90.4)).toBe(90.4)
    expect(ShotMonitor.shotTemperature(93.0, 0.0, null)).toBe(93.0) // implausible
    expect(ShotMonitor.targetPressure(9.0, 6.0)).toBe(6.0)
    expect(ShotMonitor.targetPressure(9.0, null)).toBe(9.0)
  })

  it('makes no decision without enough readings', () => {
    expect(ShotMonitor.isSettled([], 10.0)).toBe(false)
    expect(
      ShotMonitor.isSettled(
        [
          { t: 9.9, grams: 30.0 },
          { t: 10.0, grams: 30.0 },
        ],
        10.0,
      ),
    ).toBe(false) // < 4 readings
  })
})
