// BOOKOO Themis Mini BLE protocol. 1:1 port of BookooProtocol.swift / .kt (no browser APIs, unit-testable).
// Source: https://github.com/BooKooCode/OpenSource/blob/main/bookoo_mini_scale/protocols.md
// and Beanconqueror's field-tested implementation.

export const SERVICE_UUID = 0x0ffe
/** Weight notifications (20-byte packets). */
export const WEIGHT_CHAR_UUID = 0xff11
/** Commands (6-byte packets). */
export const COMMAND_CHAR_UUID = 0xff12
export const WEIGHT_PACKET_LENGTH = 20
/** Anything longer than this is rejected outright. */
export const MAX_PACKET_LENGTH = 64

/** The only commands BrewLog ever sends (write allowlist). Timer checksums don't match a plain XOR, so they're kept verbatim. */
export type Command = 'tare' | 'startTimer' | 'stopTimer' | 'resetTimer'
const COMMANDS: Record<Command, readonly number[]> = {
  tare: [0x03, 0x0a, 0x01, 0x00, 0x00, 0x08],
  startTimer: [0x03, 0x0a, 0x04, 0x00, 0x00, 0x0a],
  stopTimer: [0x03, 0x0a, 0x05, 0x00, 0x00, 0x0d],
  resetTimer: [0x03, 0x0a, 0x06, 0x00, 0x00, 0x0c],
}

/** A fresh copy, so callers can't modify the allowlisted bytes. */
export const commandPacket = (command: Command): Uint8Array<ArrayBuffer> => Uint8Array.from(COMMANDS[command])

export interface Reading {
  milliseconds: number
  grams: number
  flowRate: number
  batteryPercent: number
  /** Whether byte 20 matched the documented XOR checksum. */
  checksumValid: boolean
}

export function checksum(bytes: ArrayLike<number>, count = bytes.length): number {
  let x = 0
  for (let i = 0; i < count; i++) x ^= bytes[i]
  return x
}

/** Parses a weight notification. Returns null for anything malformed or implausible. */
export function parseReading(data: Uint8Array): Reading | null {
  if (data.length < WEIGHT_PACKET_LENGTH || data.length > MAX_PACKET_LENGTH) return null
  const b = data
  if (b[0] !== 0x03 || b[1] !== 0x0b) return null
  const ms = (b[2] << 16) | (b[3] << 8) | b[4]
  let grams = ((b[7] << 16) | (b[8] << 8) | b[9]) / 100
  if (b[6] === 0x2d) grams = -grams // '-'
  let flow = ((b[11] << 8) | b[12]) / 100
  if (b[10] === 0x2d) flow = -flow
  if (grams < -3_000 || grams > 5_000 || flow < -200 || flow > 200) return null
  return {
    milliseconds: ms,
    grams,
    flowRate: flow,
    batteryPercent: Math.min(b[13], 100),
    checksumValid: checksum(b, 19) === b[19],
  }
}

/**
 * Decides whether to enforce checksums: enforced after a short learning phase if the firmware follows
 * the documented XOR checksum; otherwise only the plausibility checks apply.
 */
export class PacketValidator {
  policy: 'learning' | 'enforced' | 'ignored' = 'learning'
  rejected = 0
  private seen = 0
  private valid = 0

  constructor(private readonly learningPackets = 10) {}

  accept(data: Uint8Array): Reading | null {
    const reading = parseReading(data)
    if (!reading) {
      this.rejected++
      return null
    }
    switch (this.policy) {
      case 'learning':
        this.seen++
        if (reading.checksumValid) this.valid++
        if (this.seen >= this.learningPackets) this.policy = this.valid * 10 >= this.seen * 9 ? 'enforced' : 'ignored'
        return reading
      case 'enforced':
        if (reading.checksumValid) return reading
        this.rejected++
        return null
      case 'ignored':
        return reading
    }
  }

  reset(): void {
    this.policy = 'learning'
    this.rejected = 0
    this.seen = 0
    this.valid = 0
  }
}
