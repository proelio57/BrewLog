import { describe, expect, it } from 'vitest'
import { DotParser, crc16, dotPacket, isDot } from '../src/scale/timemoreDot'

// Same scenarios as TimemoreDotTests.swift; command bytes verified on a physical Dot (decentespresso/decaid #739).

const weightFrame = (grams: number, timer = 0, opcode = 0x01): number[] => {
  const raw = Math.round(grams * 10) >>> 0
  const payload = [(raw >>> 24) & 0xff, (raw >>> 16) & 0xff, (raw >>> 8) & 0xff, raw & 0xff, 0, 0, timer >> 8, timer & 0xff, 0]
  return [0xa5, 0x5a, opcode, 0x01, 0x00, payload.length, ...payload, 0x00, 0x00]
}

describe('Timemore Dot', () => {
  it('builds the verified command frames', () => {
    expect([...dotPacket('tare')]).toEqual([0xa5, 0x5a, 0x03, 0x0d, 0x00, 0x00, 0x64, 0xd1])
    expect([...dotPacket('startTimer')]).toEqual([0xa5, 0x5a, 0x03, 0x02, 0x00, 0x01, 0x01, 0x18, 0x67])
    expect([...dotPacket('stopTimer')]).toEqual([0xa5, 0x5a, 0x03, 0x02, 0x00, 0x01, 0x02, 0x19, 0x27])
    expect([...dotPacket('resetTimer')]).toEqual([0xa5, 0x5a, 0x03, 0x02, 0x00, 0x01, 0x03, 0xd9, 0xe6])
    expect([...dotPacket('setUnitGrams')]).toEqual([0xa5, 0x5a, 0x03, 0x06, 0x00, 0x01, 0x00, 0xe8, 0xa7])
    expect([...dotPacket('setStandardMode')]).toEqual([0xa5, 0x5a, 0x03, 0x08, 0x00, 0x02, 0x01, 0x00, 0xeb, 0x31])
    expect([...dotPacket('requestBattery')]).toEqual([0xa5, 0x5a, 0x02, 0x05, 0x00, 0x00, 0x5a, 0x51])
    expect(crc16([0xa5, 0x5a, 0x03, 0x0d, 0x00, 0x00])).toBe(0x64d1)
  })

  it('decodes weight, timer and battery', () => {
    const parser = new DotParser()
    expect(parser.feed(weightFrame(1234.5, 42))).toEqual([{ type: 'weight', grams: 1234.5, timerSeconds: 42 }])
    expect(parser.feed(weightFrame(-12.3))).toEqual([{ type: 'weight', grams: -12.3, timerSeconds: 0 }])
    expect(parser.feed(weightFrame(1.1, 0, 0x02))).toEqual([{ type: 'weight', grams: 1.1, timerSeconds: 0 }])
    expect(parser.feed([0xa5, 0x5a, 0x01, 0x05, 0x00, 0x02, 0x00, 0x48, 0, 0])).toEqual([{ type: 'battery', percent: 72 }])
    expect(parser.feed([0xa5, 0x5a, 0x01, 0x05, 0x00, 0x01, 80, 0, 0])).toEqual([{ type: 'battery', percent: 80 }])
    expect(parser.feed([0xa5, 0x5a, 0x01, 0x05, 0x00, 0x02, 0x00, 0x65, 0, 0])).toEqual([])
    expect(parser.feed(dotPacket('tare'))).toEqual([])
  })

  it('reassembles split, packed and garbled notifications', () => {
    const parser = new DotParser()
    const frame = weightFrame(250)
    expect(parser.feed(frame.slice(0, 5))).toEqual([])
    expect(parser.feed(frame.slice(5))).toEqual([{ type: 'weight', grams: 250, timerSeconds: 0 }])
    expect(parser.feed([...weightFrame(1), ...weightFrame(2)]).map((e) => e.type === 'weight' && e.grams)).toEqual([1, 2])
    expect(parser.feed([0x00, 0xff, 0x12, ...weightFrame(3)])).toEqual([{ type: 'weight', grams: 3, timerSeconds: 0 }])
    expect(parser.feed([0xa5, 0x5a, 0x01, 0x01, 0xff, 0xff, ...weightFrame(4)])).toEqual([{ type: 'weight', grams: 4, timerSeconds: 0 }])
    expect(parser.feed(weightFrame(99_999))).toEqual([])
  })

  it('recognizes the Dot by name', () => {
    expect(isDot('TIMEMORE Dot')).toBe(true)
    expect(isDot('TES017-1A2B')).toBe(true)
    expect(isDot('BOOKOO_SC')).toBe(false)
    expect(isDot(null)).toBe(false)
  })
})
