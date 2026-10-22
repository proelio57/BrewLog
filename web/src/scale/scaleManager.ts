import { Store } from '../data/store'
import { pourSteps, type Recipe } from '../domain/recipe'
import { sanitized } from '../domain/validation'
import { COMMAND_CHAR_UUID, type Command, PacketValidator, SERVICE_UUID, WEIGHT_CHAR_UUID, commandPacket } from './bookoo'

/** Monotonic clock in milliseconds (shared by scale readings and the brew engine). */
export const monotonicMillis = (): number => performance.now()

export type ConnectionState = 'unsupported' | 'idle' | 'connecting' | 'connected'
export const CONNECTION_LABELS: Record<ConnectionState, string> = {
  unsupported: 'Bluetooth not available in this browser',
  idle: 'Not connected',
  connecting: 'Connecting…',
  connected: 'Connected',
}

export interface ScaleState {
  connection: ConnectionState
  isDemo: boolean
  weight: number
  battery: number | null
  name: string | null
  rejectedPackets: number
  error: string | null
}

/** What the brew engine needs from a scale. */
export interface ScaleCommands {
  readonly isReady: boolean
  tare(): void
  prepareForBrew(recipe: Recipe): void
  /** Tares for weighing the beans (demo: simulates beans being added). */
  prepareForDosing(dose: number): void
  dosingFinished(): void
  brewStarted(): void
  brewFinished(): void
}

export type ReadingListener = (grams: number, timeMs: number) => void

export const bluetoothSupported = (): boolean => typeof navigator !== 'undefined' && 'bluetooth' in navigator

/** Browsers hide Web Bluetooth on plain-http addresses (anything but https:// and localhost). */
export const insecureAddress = (): boolean => typeof window !== 'undefined' && window.isSecureContext === false

/**
 * BOOKOO Themis Mini over Web Bluetooth (Chrome/Edge on Android, Windows, macOS; Bluefy on iPhone),
 * plus a demo scale that pours according to the recipe.
 */
export class ScaleManager implements ScaleCommands {
  readonly state: Store<ScaleState>
  private device: BluetoothDevice | null = null
  private command: BluetoothRemoteGATTCharacteristic | null = null
  private userDisconnect = false
  private readonly validator = new PacketValidator()
  private readonly listeners = new Set<ReadingListener>()
  private readonly demo = new DemoScale((grams) => this.handle(grams, 100))

  constructor(demoEnabled: boolean, private readonly onDemoChange: (enabled: boolean) => void) {
    this.state = new Store<ScaleState>({
      connection: bluetoothSupported() ? 'idle' : 'unsupported',
      isDemo: demoEnabled, weight: 0, battery: null, name: null, rejectedPackets: 0, error: null,
    })
    if (demoEnabled) this.demo.start()
  }

  get isReady(): boolean {
    const s = this.state.get()
    return s.isDemo || s.connection === 'connected'
  }

  get displayName(): string {
    const s = this.state.get()
    return s.isDemo ? 'Demo scale' : s.name ?? 'Scale'
  }

  onReading(listener: ReadingListener): () => void {
    this.listeners.add(listener)
    return () => {
      this.listeners.delete(listener)
    }
  }

  setDemo(enabled: boolean): void {
    if (enabled) {
      void this.disconnect()
      this.demo.start()
      this.patch({ isDemo: true, battery: 100 })
    } else {
      this.demo.stop()
      this.patch({ isDemo: false, battery: null })
    }
    this.onDemoChange(enabled)
  }

  /** Opens the browser's device chooser (must be called from a tap/click). */
  async connect(): Promise<void> {
    if (!bluetoothSupported()) return
    try {
      this.patch({ error: null })
      const device = await navigator.bluetooth.requestDevice({
        filters: [{ namePrefix: 'BOOKOO' }, { namePrefix: 'bookoo' }, { namePrefix: 'Bookoo' }, { services: [SERVICE_UUID] }],
        optionalServices: [SERVICE_UUID],
      })
      this.device = device
      device.addEventListener('gattserverdisconnected', this.onDisconnected)
      await this.openConnection()
    } catch (error) {
      // User cancelled the chooser or the connection failed.
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

  tare(): void {
    if (this.state.get().isDemo) this.demo.tare()
    else void this.send('tare')
  }

  /** Tares and resets the scale timer. In demo mode it also schedules a simulated pour that follows the recipe. */
  prepareForBrew(recipe: Recipe): void {
    if (this.state.get().isDemo) {
      this.demo.simulate(recipe)
    } else {
      void this.send('tare').then(() => setTimeout(() => void this.send('resetTimer'), 150))
    }
  }

  prepareForDosing(dose: number): void {
    if (this.state.get().isDemo) this.demo.simulateDose(dose)
    else void this.send('tare')
  }

  dosingFinished(): void {
    if (this.state.get().isDemo) this.demo.stopSimulation()
  }

  brewStarted(): void {
    void this.send('startTimer')
  }

  brewFinished(): void {
    void this.send('stopTimer')
    if (this.state.get().isDemo) this.demo.stopSimulation()
  }

  /** Writes one of the allowlisted commands. No other bytes can be sent to the scale. */
  async send(command: Command): Promise<void> {
    const characteristic = this.command
    if (this.state.get().isDemo || !characteristic) return
    const packet = commandPacket(command)
    try {
      if (characteristic.properties.writeWithoutResponse) await characteristic.writeValueWithoutResponse(packet)
      else await characteristic.writeValueWithResponse(packet)
    } catch {
      // Ignore a single failed write; the scale keeps working.
    }
  }

  private async openConnection(): Promise<void> {
    const device = this.device
    if (!device?.gatt) return
    this.userDisconnect = false
    this.validator.reset()
    this.patch({ connection: 'connecting' })
    const server = await device.gatt.connect()
    const service = await server.getPrimaryService(SERVICE_UUID)
    this.command = await service.getCharacteristic(COMMAND_CHAR_UUID)
    const weight = await service.getCharacteristic(WEIGHT_CHAR_UUID)
    weight.addEventListener('characteristicvaluechanged', this.onData)
    await weight.startNotifications()
    // Advertised names are untrusted input: sanitize and bound them.
    this.patch({ connection: 'connected', name: sanitized(device.name ?? 'BOOKOO', 40) || 'BOOKOO' })
  }

  private onData = (event: Event): void => {
    const value = (event.target as BluetoothRemoteGATTCharacteristic).value
    if (!value) return
    const reading = this.validator.accept(new Uint8Array(value.buffer, value.byteOffset, value.byteLength))
    if (!reading) {
      this.patch({ rejectedPackets: this.validator.rejected })
      return
    }
    this.handle(reading.grams, reading.batteryPercent)
  }

  private onDisconnected = (): void => {
    this.command = null
    if (this.userDisconnect || this.state.get().isDemo) {
      this.patch({ connection: 'idle' })
      return
    }
    // Unexpected disconnect (scale off or out of range): try to reconnect a few times.
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

  private handle(grams: number, battery: number | null): void {
    if (!Number.isFinite(grams)) return
    const patch: Partial<ScaleState> = { weight: grams }
    if (battery != null) patch.battery = Math.min(Math.max(battery, 0), 100)
    this.patch(patch)
    const now = monotonicMillis()
    this.listeners.forEach((listener) => listener(grams, now))
  }

  private patch(patch: Partial<ScaleState>): void {
    this.state.update((s) => ({ ...s, ...patch }))
  }
}

/** Simulates a scale that pours according to the recipe. Port of DemoScale. */
class DemoScale {
  private timer: ReturnType<typeof setInterval> | null = null
  private weight = 0
  private plan: { start: number; goal: number; rate: number }[] = []
  private pourStart: number | null = null
  private endTime = 0

  constructor(private readonly onWeight: (grams: number) => void) {}

  start(): void {
    if (this.timer) return
    this.timer = setInterval(() => this.tick(), 100)
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    this.stopSimulation()
  }

  tare(): void {
    this.weight = 0
  }

  simulate(recipe: Recipe, delaySeconds = 2.5): void {
    this.weight = 0
    const espresso = recipe.method === 'espresso'
    const low = espresso ? Math.max(recipe.flowMin, 1) : Math.max(recipe.flowMin, 2)
    const high = Math.max(recipe.flowMax, low + 0.5)
    const random = (a: number, b: number) => a + Math.random() * (b - a)
    // Pour-over: the first pour starts right away. Espresso: the first drops come after the pre-infusion.
    this.plan = pourSteps(recipe).map((step, index) => ({
      start: index === 0 && !espresso ? 0 : step.time + random(-1, 2.5),
      goal: (step.target ?? 0) + random(-1.5, 2.5),
      rate: random(low, high),
    }))
    this.endTime = recipe.targetTime + 20
    this.pourStart = monotonicMillis() + delaySeconds * 1000
  }

  /** Beans trickling into a cup, ending a little off the dose like a real hand would. */
  simulateDose(dose: number, delaySeconds = 1.5): void {
    this.weight = 0
    const random = (a: number, b: number) => a + Math.random() * (b - a)
    this.plan = [{ start: 0, goal: Math.max(dose + random(-0.3, 0.4), 0), rate: random(1.5, 2.5) }]
    this.endTime = 60
    this.pourStart = monotonicMillis() + delaySeconds * 1000
  }

  stopSimulation(): void {
    this.plan = []
    this.pourStart = null
  }

  private tick(): void {
    if (this.pourStart != null) {
      const now = monotonicMillis()
      if (now >= this.pourStart) {
        const t = (now - this.pourStart) / 1000
        const active = [...this.plan].reverse().find((p) => p.start <= t)
        if (active && this.weight < active.goal) {
          this.weight = Math.min(active.goal, this.weight + active.rate * 0.1 * (0.75 + Math.random() * 0.5))
        }
        if (t > this.endTime) this.stopSimulation()
      }
    }
    const noise = (Math.random() - 0.5) * 0.06
    this.onWeight(Math.round((this.weight + noise) * 10) / 10)
  }
}
