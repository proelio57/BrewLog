// Timemore Black Mirror Dot (TES017). Port of TimemoreDotProtocol.swift; community-documented protocol
// (decentespresso/decaid #739, Sofronio/dot-scale-mate), not an official Timemore spec.
// Frames: A5 5A | opcode | cmd | length (2, big-endian) | payload | 2-byte tail. Commands carry a CRC-16/MODBUS tail;
// notifications leave it at 00 00, so incoming frames are checked for shape and plausibility, not CRC.

export const DOT_SERVICE_UUID = 0xfff0
export const DOT_NOTIFY_CHAR_UUID = 0xfff1
export const DOT_COMMAND_CHAR_UUID = 0xfff2
const HEADER = 6
const TAIL = 2
const MAX_PAYLOAD = 64
const MAX_BUFFER = 256

export const isDot = (name: string | null | undefined): boolean => {
  const lower = (name ?? '').toLowerCase()
  return lower.includes('dot') || lower.includes('tes017')
}

export function crc16(bytes: ArrayLike<number>): number {
  let crc = 0xffff
  for (let i = 0; i < bytes.length; i++) {
    crc ^= bytes[i] & 0xff
    for (let bit = 0; bit < 8; bit++) crc = crc & 1 ? (crc >>> 1) ^ 0xa001 : crc >>> 1
  }
  return crc & 0xffff
}

export function frame(opcode: number, cmd: number, payload: number[] = []): Uint8Array<ArrayBuffer> {
  const body = [0xa5, 0x5a, opcode, cmd, (payload.length >> 8) & 0xff, payload.length & 0xff, ...payload]
  const crc = crc16(body)
  return Uint8Array.from([...body, (crc >> 8) & 0xff, crc & 0xff])
}

export type DotCommand = 'tare' | 'startTimer' | 'stopTimer' | 'resetTimer' | 'setUnitGrams' | 'setStandardMode' | 'requestBattery'

export function dotPacket(command: DotCommand): Uint8Array<ArrayBuffer> {
  switch (command) {
    case 'tare': return frame(0x03, 0x0d)
    case 'startTimer': return frame(0x03, 0x02, [0x01])
    case 'stopTimer': return frame(0x03, 0x02, [0x02])
    case 'resetTimer': return frame(0x03, 0x02, [0x03])
    case 'setUnitGrams': return frame(0x03, 0x06, [0x00])
    case 'setStandardMode': return frame(0x03, 0x08, [0x01, 0x00])
    case 'requestBattery': return frame(0x02, 0x05)
  }
}

/** The Dot only sends weight after unit and mode are set: [command, delay before it in ms]. */
export const DOT_INIT_SEQUENCE: [DotCommand, number][] = [['setUnitGrams', 500], ['setStandardMode', 200], ['requestBattery', 100]]

export type DotEvent = { type: 'weight'; grams: number; timerSeconds: number } | { type: 'battery'; percent: number }

export function dotEvent(opcode: number, cmd: number, payload: number[]): DotEvent | null {
  if (opcode === 0x03) return null // command ack
  if (cmd === 0x01) {
    if (payload.length < 8) return null
    const raw = (payload[0] << 24) | (payload[1] << 16) | (payload[2] << 8) | payload[3] // signed 32-bit
    const grams = raw / 10
    if (grams < -3000 || grams > 5000) return null
    return { type: 'weight', grams, timerSeconds: (payload[6] << 8) | payload[7] }
  }
  if (cmd === 0x05) {
    const raw = payload.length >= 2 ? payload[1] : payload[0]
    return raw != null && raw <= 100 ? { type: 'battery', percent: raw } : null
  }
  return null
}

/** Reassembles frames that are split across or packed into notifications, and resyncs on garbage. */
export class DotParser {
  private buffer: number[] = []

  feed(data: ArrayLike<number>): DotEvent[] {
    for (let i = 0; i < data.length; i++) this.buffer.push(data[i] & 0xff)
    if (this.buffer.length > MAX_BUFFER) this.buffer.splice(0, this.buffer.length - MAX_BUFFER)
    const events: DotEvent[] = []
    while (this.buffer.length >= HEADER) {
      if (this.buffer[0] !== 0xa5 || this.buffer[1] !== 0x5a) { this.buffer.shift(); continue }
      const length = (this.buffer[4] << 8) | this.buffer[5]
      if (length > MAX_PAYLOAD) { this.buffer.shift(); continue }
      const total = HEADER + length + TAIL
      if (this.buffer.length < total) break
      const [, , opcode, cmd] = this.buffer
      const payload = this.buffer.slice(HEADER, HEADER + length)
      this.buffer.splice(0, total)
      const event = dotEvent(opcode, cmd, payload)
      if (event) events.push(event)
    }
    return events
  }

  reset(): void {
    this.buffer = []
  }
}
