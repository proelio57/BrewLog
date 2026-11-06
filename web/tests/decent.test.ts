import { describe, expect, it } from 'vitest'
import { DecentProtocol } from '../src/machine/decent'
import type { MachineStatus } from '../src/domain/models'

describe('DecentProtocol', () => {
  const bytes = (...values: number[]): Uint8Array => Uint8Array.from(values)

  it('decodes shot sample', () => {
    const data = bytes(
      0x00, 0x64, // SampleTime
      0x90, 0x00, // GroupPressure 9.0 (0x9000 = 36864; 36864 / 4096 = 9.0)
      0x20, 0x00, // GroupFlow 2.0 (0x2000 = 8192; 8192 / 4096 = 2.0)
      0x5d, 0x00, // MixTemp 93.0 (0x5d00 = 23808; 23808 / 256 = 93.0)
      0x5d, 0x80, 0x00, // HeadTemp 93.5 (0x5d8000 = 6127616; 6127616 / 65536 = 93.5)
      0x5d, 0x00, // SetMixTemp 93.0
      0x5d, 0x80, // SetHeadTemp 93.5
      0x90, // SetGroupPressure 9.0 (144 / 16 = 9.0)
      0x00, // SetGroupFlow 0
      0x03, // FrameNumber
      0x82, // SteamTemp
    )

    const sample = DecentProtocol.sample(data)
    expect(sample).not.toBeNull()
    expect(sample!.pressure).toBeCloseTo(9.0, 3)
    expect(sample!.flow).toBeCloseTo(2.0, 3)
    expect(sample!.mixTemp).toBeCloseTo(93.0, 3)
    expect(sample!.headTemp).toBeCloseTo(93.5, 3)
    expect(sample!.targetMixTemp).toBeCloseTo(93.0, 3)
    expect(sample!.targetHeadTemp).toBeCloseTo(93.5, 3)
    expect(sample!.targetPressure).toBeCloseTo(9.0, 3)
    expect(sample!.targetFlow).toBeCloseTo(0.0, 3)
    expect(sample!.frame).toBe(3)

    let status: MachineStatus = {
      connected: true,
      online: true,
      temperature: null,
      targetTemperature: null,
      pressure: null,
      targetPressure: null,
      flow: null,
      weight: null,
      mode: 1,
      profile: null,
      hasPressure: null,
      processActive: false,
      processKind: null,
      processLabel: null,
      processIsUtility: false,
      scaleConnected: false,
      systemState: null,
      systemMessage: null,
      capabilities: ['startStop'],
    }
    status = DecentProtocol.apply(sample!, status)
    expect(status.pressure).toBeCloseTo(9.0, 3)
    expect(status.temperature).toBeCloseTo(93.5, 3)
    expect(status.targetTemperature).toBeCloseTo(93.5, 3)
    expect(status.targetPressure).toBeCloseTo(9.0, 3)
    expect(status.hasPressure).toBe(true)
  })

  it('maps states to shot', () => {
    let status = DecentProtocol.apply(4, 4)
    expect(status.processActive).toBe(true)
    expect(status.processKind).toBe('infusion')

    status = DecentProtocol.apply(4, 5, status)
    expect(status.processActive).toBe(true)
    expect(status.processKind).toBe('brew')

    status = DecentProtocol.apply(2, 0, status)
    expect(status.processActive).toBe(false)
    expect(status.mode).toBe(1) // brew / idle

    status = DecentProtocol.apply(0, 0, status)
    expect(status.mode).toBe(0) // standby
  })

  it('treats flush as not a shot', () => {
    let status = DecentProtocol.apply(15, 6)
    expect(status.processIsUtility).toBe(true)
    expect(status.processActive).toBe(true)

    status = DecentProtocol.apply(6, 0, status)
    expect(status.processActive).toBe(false)
    expect(status.mode).toBe(3) // water

    status = DecentProtocol.apply(5, 7, status)
    expect(status.processIsUtility).toBe(true)
    expect(status.mode).toBe(2) // steam
  })

  it('ends shot on error state', () => {
    let status = DecentProtocol.apply(4, 5)
    status = DecentProtocol.apply(11, 0, status)
    expect(status.processActive).toBe(false)
    expect(status.systemState).toBe('error')

    status = DecentProtocol.apply(4, 205, status)
    expect(status.processActive).toBe(false)
    expect(status.systemMessage?.toLowerCase()).toContain('pressure sensor')

    status = DecentProtocol.apply(2, 0, status)
    expect(status.systemMessage).toBeNull()
  })

  it('ignores short packets', () => {
    expect(DecentProtocol.sample(new Uint8Array(18))).toBeNull()
    expect(DecentProtocol.state(new Uint8Array([4]))).toBeNull()
    const st = DecentProtocol.state(new Uint8Array([4, 5]))
    expect(st).not.toBeNull()
    expect(st!.state).toBe(4)
    expect(st!.substate).toBe(5)
  })

  it('generates commands', () => {
    expect(DecentProtocol.command('standby')).toEqual(Uint8Array.from([0]))
    expect(DecentProtocol.command('brew')).toEqual(Uint8Array.from([2]))
    expect(DecentProtocol.command('steam')).toEqual(Uint8Array.from([5]))
    expect(DecentProtocol.command('water')).toEqual(Uint8Array.from([6]))
    expect(DecentProtocol.startShot).toEqual(Uint8Array.from([4]))
    expect(DecentProtocol.stopShot).toEqual(Uint8Array.from([2]))
  })
})
