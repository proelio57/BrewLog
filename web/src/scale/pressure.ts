import { Store } from '../data/store'
import type { Recipe } from '../domain/recipe'
import { sanitized } from '../domain/validation'
import { bluetoothSupported, monotonicMillis, type ConnectionState } from './scaleManager'

// BOOKOO Espresso Monitor (pressure sensor). Same protocol as BookooMonitorProtocol.swift / BookooPressureProtocol.kt,
// from BOOKOO's published spec (espresso_monitor/protocols.md):
// service 0x0FFF, commands on 0xFF01, data notifications on 0xFF02;
// data `02 1B 00 00 <bar×100 hi> <lo> <battery> 00 00 00`; start `02 0C 01 00 00 00 0F`, stop `02 0C 00 00 00 00 0E`.

export const MONITOR_SERVICE = 0x0fff
export const MONITOR_COMMAND = 0xff01
export const MONITOR_DATA = 0xff02
export const START_COMMAND = [0x02, 0x0c, 0x01, 0x00, 0x00, 0x00, 0x0f]
export const STOP_COMMAND = [0x02, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x0e]

export interface PressureReading { bar: number; batteryPercent: number }

export function parsePressurePacket(bytes: Uint8Array | number[]): PressureReading | null {
  if (bytes.length < 7 || bytes.length > 20 || bytes[0] !== 0x02 || bytes[1] !== 0x1b) return null
  const bar = ((bytes[4] << 8) | bytes[5]) / 100
  if (bar < 0 || bar > 20) return null
  return { bar, batteryPercent: Math.min(bytes[6], 100) }
}

/** XOR of all bytes but the last, which is how BOOKOO checksums its commands. */
export const commandChecksum = (bytes: number[]): number => bytes.slice(0, -1).reduce((a, b) => a ^ b, 0)

export const isMonitorName = (name: string | null | undefined): boolean =>
  !!name && (name.toLowerCase().startsWith('bookoo_em') || name.toLowerCase().includes('espresso monitor'))

export interface PressureState {
  enabled: boolean
  isDemo: boolean
  connection: ConnectionState
  pressure: number
  battery: number | null
  name: string | null
  error: string | null
}

export type PressureListener = (bar: number, timeMs: number) => void

/** Web Bluetooth connection to the sensor (or a demo sensor). Runs next to the scale connection. */
export class PressureMonitor {
  readonly state: Store<PressureState>
  private device: BluetoothDevice | null = null
  private command: BluetoothRemoteGATTCharacteristic | null = null
  private userDisconnect = false
  private readonly listeners = new Set<PressureListener>()
  private readonly demo = new DemoPressureSensor((bar) => this.handle(bar, 100))

  constructor(enabled: boolean, demo: boolean, private readonly persist: (enabled: boolean, demo: boolean) => void) {
    this.state = new Store<PressureState>({
      enabled, isDemo: demo, connection: bluetoothSupported() ? 'idle' : 'unsupported', pressure: 0, battery: null, name: null, error: null,
    })
    if (enabled && demo) this.demo.start()
  }

  /** Live pressure is available. */
  get isReady(): boolean {
    const s = this.state.get()
    return s.enabled && (s.isDemo || s.connection === 'connected')
  }

  get displayName(): string {
    const s = this.state.get()
    return s.isDemo ? 'Demo sensor' : s.name ?? 'Pressure sensor'
  }

  onPressure(listener: PressureListener): () => void {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  configure(enabled: boolean, demo: boolean): void {
    this.demo.stop()
    if (!enabled || demo) void this.disconnect()
    this.patch({ enabled, isDemo: demo, pressure: 0 })
    if (enabled && demo) this.demo.start()
    this.persist(enabled, demo)
  }

  /** Opens the browser's device chooser (must be called from a tap/click). */
  async connect(): Promise<void> {
    if (!bluetoothSupported()) return
    try {
      this.patch({ error: null })
      const device = await navigator.bluetooth.requestDevice({
        filters: [{ namePrefix: 'BOOKOO_EM' }, { namePrefix: 'bookoo_em' }, { services: [MONITOR_SERVICE] }],
        optionalServices: [MONITOR_SERVICE],
      })
      this.device = device
      device.addEventListener('gattserverdisconnected', this.onDisconnected)
      await this.openConnection()
    } catch (error) {
      if (error instanceof Error && error.name !== 'NotFoundError') this.patch({ error: error.message.slice(0, 200) })
      if (this.state.get().connection === 'connecting') this.patch({ connection: 'idle' })
    }
  }

  async disconnect(): Promise<void> {
    this.userDisconnect = true
    this.device?.removeEventListener('gattserverdisconnected', this.onDisconnected)
    if (this.device?.gatt?.connected) this.device.gatt.disconnect()
    this.device = null
    this.command = null
    this.patch({ connection: bluetoothSupported() ? 'idle' : 'unsupported', name: null })
  }

  prepareForShot(recipe: Recipe): void {
    const s = this.state.get()
    if (s.enabled && s.isDemo) this.demo.simulateShot(recipe)
  }

  shotFinished(): void { this.demo.stopShot() }

  private async openConnection(): Promise<void> {
    const device = this.device
    if (!device?.gatt) return
    this.userDisconnect = false
    this.patch({ connection: 'connecting' })
    const server = await device.gatt.connect()
    const service = await server.getPrimaryService(MONITOR_SERVICE)
    this.command = await service.getCharacteristic(MONITOR_COMMAND)
    const data = await service.getCharacteristic(MONITOR_DATA)
    data.addEventListener('characteristicvaluechanged', this.onData)
    await data.startNotifications()
    // The sensor only streams after the start command.
    await this.write(START_COMMAND)
    this.patch({ connection: 'connected', name: sanitized(device.name ?? 'Espresso Monitor', 40) || 'Espresso Monitor' })
  }

  private async write(bytes: number[]): Promise<void> {
    const characteristic = this.command
    if (!characteristic) return
    try {
      if (characteristic.properties.write) await characteristic.writeValueWithResponse(new Uint8Array(bytes))
      else await characteristic.writeValueWithoutResponse(new Uint8Array(bytes))
    } catch {
      // A failed write leaves the sensor idle; reconnecting sends the start command again.
    }
  }

  private onData = (event: Event): void => {
    const value = (event.target as BluetoothRemoteGATTCharacteristic).value
    if (!value) return
    const reading = parsePressurePacket(new Uint8Array(value.buffer, value.byteOffset, value.byteLength))
    if (reading) this.handle(reading.bar, reading.batteryPercent)
  }

  private onDisconnected = (): void => {
    this.command = null
    if (this.userDisconnect || this.state.get().isDemo) {
      this.patch({ connection: 'idle' })
      return
    }
    this.patch({ connection: 'connecting' })
    let attempts = 0
    const retry = () => {
      if (this.userDisconnect || !this.device) return
      attempts++
      this.openConnection().catch(() => {
        if (attempts < 5) setTimeout(retry, 2_000)
        else this.patch({ connection: 'idle' })
      })
    }
    setTimeout(retry, 1_000)
  }

  private handle(bar: number, battery: number | null): void {
    if (!Number.isFinite(bar)) return
    const patch: Partial<PressureState> = { pressure: bar }
    if (battery != null) patch.battery = Math.min(Math.max(battery, 0), 100)
    this.patch(patch)
    const now = monotonicMillis()
    this.listeners.forEach((listener) => listener(bar, now))
  }

  private patch(patch: Partial<PressureState>): void {
    this.state.update((s) => ({ ...s, ...patch }))
  }
}

/** Idles at 0 bar and follows a realistic shot profile when a shot is simulated. */
class DemoPressureSensor {
  private timer: ReturnType<typeof setInterval> | null = null
  private shotStart: number | null = null
  private preinfusion = 6
  private peak = 9
  private duration = 28

  constructor(private readonly onPressure: (bar: number) => void) {}

  start(): void { if (!this.timer) this.timer = setInterval(() => this.tick(), 200) }

  stop(): void {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    this.shotStart = null
  }

  simulateShot(recipe: Recipe): void {
    if (this.shotStart != null && Date.now() >= this.shotStart) return
    const extract = recipe.steps.find((s) => s.kind === 'extract')?.time ?? 6
    this.preinfusion = Math.max(extract - 1, 2)
    this.peak = recipe.pressure ?? 9
    this.duration = recipe.targetTime + (Math.random() * 3.5 - 1.5)
    this.shotStart = Date.now() + 2_500
  }

  stopShot(): void { this.shotStart = null }

  private tick(): void {
    let bar = 0
    if (this.shotStart != null && Date.now() >= this.shotStart) {
      const t = (Date.now() - this.shotStart) / 1000
      if (t >= this.duration) this.shotStart = null
      else if (t < this.preinfusion) bar = Math.min(t / 1.5, 1) * 3
      else if (t < this.preinfusion + 2.5) bar = 3 + ((this.peak - 3) * (t - this.preinfusion)) / 2.5
      else bar = this.peak * (1 - 0.18 * ((t - this.preinfusion - 2.5) / Math.max(this.duration - this.preinfusion - 2.5, 1)))
      bar = Math.max(bar + (Math.random() * 0.2 - 0.1), 0)
    }
    this.onPressure(Math.round(bar * 100) / 100)
  }
}
