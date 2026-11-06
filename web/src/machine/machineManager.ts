import { Store } from '../data/store'
import type { Recipe } from '../domain/recipe'
import {
  type MachineKind,
  MACHINE_TITLES,
  machineReadsPressure,
  machineCanControl,
} from '../domain/models'
import {
  type GaggiMateStatus,
  emptyStatus,
  gaggiMateUrl,
  isBrewing,
  isTelemetry,
  makeProfile,
  mergeStatus,
  statusFrame,
} from './gaggimate'
import { GaggiMateProfileImport, type MachineProfileSummary } from './gaggimateProfileImport'
import { DecentConnection } from './decent'

export type { MachineKind }
export type MachineConnection = 'off' | 'connecting' | 'connected' | 'unreachable'

export interface MachineState {
  kind: MachineKind
  host: string
  connection: MachineConnection
  status: GaggiMateStatus
  /** Feedback for the last command, e.g. "Profile sent". */
  notice: string | null
  /** The machine refused to start because of a warning (e.g. low water). */
  startBlockedBy: string[]
  profiles: MachineProfileSummary[]
  profilesLoading: boolean
}

export type ShotListener = (started: boolean, timeMs: number) => void
export type ReadingListener = (status: GaggiMateStatus, timeMs: number) => void

/** ws:// from an https page is blocked by every browser (mixed content). */
export const machineBlockedByHttps = (): boolean => typeof window !== 'undefined' && window.location.protocol === 'https:'

export class MachineManager {
  readonly state: Store<MachineState>
  readonly decent = new DecentConnection()
  private socket: WebSocket | null = null
  private lastMessage = 0
  private watchdog: ReturnType<typeof setInterval> | null = null
  private retry: ReturnType<typeof setTimeout> | null = null
  private readonly shotListeners = new Set<ShotListener>()
  private readonly readingListeners = new Set<ReadingListener>()
  private readonly pending = new Map<string, (message: Record<string, unknown> | null) => void>()
  private nextRequest = 0
  private readonly demo = new DemoMachine((status, telemetry) => this.apply(status, telemetry))

  constructor(
    kind: MachineKind,
    host: string,
    private readonly persist: (kind: MachineKind, host: string) => void,
    private readonly clock: () => number = () => performance.now(),
  ) {
    this.state = new Store<MachineState>({
      kind,
      host,
      connection: 'off',
      status: emptyStatus(),
      notice: null,
      startBlockedBy: [],
      profiles: [],
      profilesLoading: false,
    })

    this.decent.onStatus = (status, telemetry) => {
      if (this.state.get().kind === 'decent') {
        this.apply(status as unknown as GaggiMateStatus, telemetry)
      }
    }
    this.decent.onDisconnect = () => {
      if (this.state.get().kind === 'decent') {
        this.connectionLost()
      }
    }
  }

  get isConnected(): boolean {
    if (this.state.get().kind === 'decent') return this.decent.isConnected
    return this.state.get().connection === 'connected'
  }
  get status(): GaggiMateStatus {
    return this.state.get().status
  }
  get displayName(): string {
    const kind = this.state.get().kind
    return MACHINE_TITLES[kind] ?? 'No machine'
  }
  get canControl(): boolean {
    return machineCanControl(this.state.get().kind, this.isConnected)
  }
  get readsPressure(): boolean {
    return machineReadsPressure(this.state.get().kind, this.status)
  }

  onShot(listener: ShotListener): () => void {
    this.shotListeners.add(listener)
    return () => this.shotListeners.delete(listener)
  }

  onReading(listener: ReadingListener): () => void {
    this.readingListeners.add(listener)
    return () => this.readingListeners.delete(listener)
  }

  start(): void {
    this.restart()
  }

  configure(kind: MachineKind, host: string): void {
    this.state.set({ ...this.state.get(), kind, host })
    this.persist(kind, host)
    this.restart()
  }

  /** Demo machine: simulate a shot for this recipe (a real machine is started by hand or with startShot). */
  prepareForShot(recipe: Recipe): void {
    if (this.state.get().kind === 'demo') this.demo.simulateShot(recipe)
  }

  cancelShot(): void {
    if (this.state.get().kind === 'demo') this.demo.stopShot()
  }

  // MARK: Control

  setMode(mode: number): void {
    if (this.state.get().kind === 'demo') return this.demo.setMode(mode)
    if (this.state.get().kind === 'decent') return
    this.send({ tp: 'req:change-mode', mode })
  }

  startShot(ignoreWarnings = false): void {
    this.patch({ startBlockedBy: [] })
    if (this.state.get().kind === 'demo') return this.demo.startShotNow()
    if (this.state.get().kind === 'decent') {
      void this.decent.startShot()
      return
    }
    if (this.status.mode !== 1) this.send({ tp: 'req:change-mode', mode: 1 })
    this.send({ tp: 'req:process:activate', ignoreWarnings })
  }

  stopShot(): void {
    if (this.state.get().kind === 'demo') return this.demo.stopShot()
    if (this.state.get().kind === 'decent') {
      void this.decent.stopShot()
      return
    }
    this.send({ tp: 'req:process:deactivate' })
  }

  tareScale(): void {
    if (this.state.get().kind === 'gaggimate') this.send({ tp: 'req:scale:tare' })
  }

  dismissStartWarning(): void {
    this.patch({ startBlockedBy: [] })
    this.send({ tp: 'req:brew:confirm:cancel' })
  }

  nudgeTemperature(up: boolean): void {
    if (this.state.get().kind === 'demo') return this.demo.nudgeTemperature(up)
    if (this.state.get().kind === 'gaggimate') {
      this.send({ tp: up ? 'req:raise-temp' : 'req:lower-temp' })
    }
  }

  setTargetTemperature(value: number): void {
    if (this.state.get().kind === 'demo') return this.demo.setTargetTemperature(value)
  }

  /** Saves the recipe as a GaggiMate profile (updating the one sent before) and selects it. */
  sendProfile(recipe: Recipe, dose: number, temperature: number): void {
    if (this.state.get().kind === 'demo') {
      this.demo.setTargetTemperature(temperature)
      this.patch({ notice: `Demo machine: ${recipe.name} selected` })
      return
    }
    if (this.state.get().kind !== 'gaggimate') return

    const status = this.status
    const profile = makeProfile(recipe, dose, temperature, status.hasPressure ?? true, status.scaleConnected)
    const key = `brewlog.machineProfile.${recipe.id}`
    const savedId = localStorage.getItem(key)
    if (savedId) profile.id = savedId
    this.patch({ notice: `Sending ${recipe.name}…` })
    this.send({ tp: 'req:profiles:save', profile }, (response) => {
      const saved =
        response && !response.error && typeof response.profile === 'object' && response.profile
          ? (response.profile as Record<string, unknown>).id
          : null
      if (typeof saved !== 'string') {
        if (savedId) {
          localStorage.removeItem(key)
          this.sendProfile(recipe, dose, temperature)
        } else {
          this.patch({
            notice: `The machine didn't accept the profile${typeof response?.error === 'string' ? `: ${response.error}` : '.'}`,
          })
        }
        return
      }
      localStorage.setItem(key, saved)
      this.send({ tp: 'req:profiles:select', id: saved }, () =>
        this.patch({ notice: `${recipe.name} is selected on the machine` }),
      )
    })
  }

  refreshProfiles(): void {
    const kind = this.state.get().kind
    if (kind === 'demo') {
      this.patch({
        profiles: [
          {
            id: 'demo-1',
            label: 'Classic 9 Bar',
            isSelected: true,
            isFavorite: true,
            isBrewLogs: false,
            recipe: null,
          },
          {
            id: 'demo-2',
            label: 'Blooming Shot',
            isSelected: false,
            isFavorite: true,
            isBrewLogs: false,
            recipe: null,
          },
          {
            id: 'demo-3',
            label: 'Turbo Shot',
            isSelected: false,
            isFavorite: false,
            isBrewLogs: false,
            recipe: null,
          },
        ],
      })
      return
    }
    if (kind !== 'gaggimate' || !this.isConnected) return

    this.patch({ profilesLoading: true })
    this.send({ tp: 'req:profiles:list' }, (response) => {
      this.patch({ profilesLoading: false })
      if (!response) return
      const summaries = GaggiMateProfileImport.summaries(response)
      this.patch({ profiles: summaries })
    })
  }

  selectProfile(id: string): void {
    const kind = this.state.get().kind
    if (kind === 'demo') {
      const updated = this.state.get().profiles.map((p) => ({ ...p, isSelected: p.id === id }))
      this.patch({ profiles: updated })
      return
    }
    if (kind === 'gaggimate' && this.isConnected) {
      this.send({ tp: 'req:profiles:select', id }, () => {
        this.refreshProfiles()
      })
    }
  }

  // MARK: Connection lifecycle

  private restart(): void {
    this.disconnect()
    this.demo.stop()
    const { kind } = this.state.get()
    if (kind === 'demo') {
      this.patch({ connection: 'connected' })
      this.demo.start()
      this.refreshProfiles()
    } else if (kind === 'gaggimate') {
      this.connect()
    } else if (kind === 'decent') {
      this.patch({ connection: this.decent.isConnected ? 'connected' : 'off' })
    } else {
      this.patch({ connection: 'off', status: emptyStatus(), profiles: [] })
    }
  }

  private connect(): void {
    if (this.socket) return
    const { kind, host } = this.state.get()
    if (kind !== 'gaggimate') return
    const url = gaggiMateUrl(host)
    if (!url) {
      this.patch({ connection: 'unreachable', status: emptyStatus() })
      return
    }

    this.patch({ connection: 'connecting' })
    let socket: WebSocket
    try {
      socket = new WebSocket(url)
    } catch {
      this.connectionLost()
      return
    }
    this.socket = socket

    socket.onopen = () => {
      if (this.socket !== socket) return
      this.lastMessage = this.clock()
      this.patch({ connection: 'connected' })
      this.watchdog = setInterval(() => {
        if (this.clock() - this.lastMessage > 12_000) this.connectionLost()
      }, 3_000)
      this.refreshProfiles()
    }

    socket.onmessage = (event) => {
      if (this.socket !== socket) return
      this.lastMessage = this.clock()
      if (typeof event.data !== 'string') return
      const frame = statusFrame(event.data)
      if (frame) {
        const next = mergeStatus(this.status, frame)
        this.apply(next, isTelemetry(frame))
      } else {
        try {
          const raw = JSON.parse(event.data) as Record<string, unknown>
          if (raw && typeof raw === 'object' && !Array.isArray(raw)) this.handleOther(raw)
        } catch {
          // ignore
        }
      }
    }

    socket.onerror = () => {
      if (this.socket === socket) this.connectionLost()
    }

    socket.onclose = () => {
      if (this.socket === socket) this.connectionLost()
    }
  }

  private disconnect(): void {
    for (const complete of this.pending.values()) complete(null)
    this.pending.clear()
    if (this.watchdog) clearInterval(this.watchdog)
    this.watchdog = null
    if (this.retry) clearTimeout(this.retry)
    this.retry = null
    const socket = this.socket
    this.socket = null
    socket?.close()
  }

  private connectionLost(): void {
    const wasBrewing = isBrewing(this.status)
    this.disconnect()
    this.patch({ connection: 'unreachable', status: emptyStatus() })
    if (wasBrewing) this.shotListeners.forEach((l) => l(false, this.clock()))
    this.retry = setTimeout(() => {
      if (this.state.get().kind === 'gaggimate') this.connect()
    }, 5_000)
  }

  private apply(status: GaggiMateStatus, telemetry: boolean): void {
    const wasBrewing = isBrewing(this.status)
    this.patch({ status, connection: 'connected' })
    const now = this.clock()
    if (telemetry) this.readingListeners.forEach((l) => l(status, now))
    if (isBrewing(status) !== wasBrewing) this.shotListeners.forEach((l) => l(isBrewing(status), now))
  }

  private handleOther(message: Record<string, unknown>): void {
    const type = message.tp
    if (type === 'evt:brew:confirm') {
      const warn = Array.isArray(message.warn) ? message.warn : []
      this.patch({
        startBlockedBy: warn
          .map((w) => (typeof w === 'object' && w && typeof (w as { k?: unknown }).k === 'string' ? (w as { k: string }).k : ''))
          .filter(Boolean),
      })
    } else if (type === 'evt:brew:confirm:cancel') {
      this.patch({ startBlockedBy: [] })
    } else if (typeof type === 'string' && type.startsWith('res:') && typeof message.rid === 'string') {
      const complete = this.pending.get(message.rid)
      this.pending.delete(message.rid)
      complete?.(message)
    }
  }

  private send(payload: Record<string, unknown>, complete?: (message: Record<string, unknown> | null) => void): void {
    const socket = this.socket
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      this.patch({ notice: "The machine isn't connected." })
      complete?.(null)
      return
    }
    const message = { ...payload }
    if (complete) {
      const rid = `bl${++this.nextRequest}`
      message.rid = rid
      this.pending.set(rid, complete)
      setTimeout(() => {
        const waiting = this.pending.get(rid)
        this.pending.delete(rid)
        waiting?.(null)
      }, 8_000)
    }
    socket.send(JSON.stringify(message))
  }

  private patch(patch: Partial<MachineState>): void {
    this.state.set({ ...this.state.get(), ...patch })
  }
}

/** Simulated machine: idles at brew temperature and runs a realistic pressure profile during a simulated shot. */
class DemoMachine {
  private timer: ReturnType<typeof setInterval> | null = null
  private status: GaggiMateStatus = emptyStatus()
  private shotStart: number | null = null
  private preinfusion = 7
  private peak = 9
  private duration = 28

  constructor(private readonly emit: (status: GaggiMateStatus, telemetry: boolean) => void) {}

  start(): void {
    this.status = {
      ...emptyStatus(),
      mode: 1,
      profile: 'Demo',
      hasPressure: true,
      targetTemperature: 93,
      temperature: 93,
      pressure: 0,
      flow: 0,
    }
    if (!this.timer) this.timer = setInterval(() => this.tick(), 500)
    this.emit(this.status, false)
  }

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

  startShotNow(): void {
    if (this.shotStart == null) this.shotStart = Date.now()
  }

  stopShot(): void {
    this.shotStart = null
    this.status = { ...this.status, processActive: false, pressure: 0, flow: 0 }
  }

  setMode(mode: number): void {
    this.status = { ...this.status, mode }
    this.emit(this.status, false)
  }

  nudgeTemperature(up: boolean): void {
    this.setTargetTemperature((this.status.targetTemperature ?? 93) + (up ? 1 : -1))
  }

  setTargetTemperature(value: number): void {
    this.status = { ...this.status, targetTemperature: value }
    this.emit(this.status, false)
  }

  private tick(): void {
    const target = this.status.targetTemperature ?? 93
    const noise = (n: number) => (Math.random() * 2 - 1) * n
    if (this.shotStart != null && Date.now() >= this.shotStart) {
      const t = (Date.now() - this.shotStart) / 1000
      if (t >= this.duration) {
        this.stopShot()
        this.status = { ...this.status, processLabel: 'Finished' }
      } else {
        let pressure: number
        if (t < this.preinfusion) pressure = Math.min(t / 1.5, 1) * 3
        else if (t < this.preinfusion + 2.5) pressure = 3 + ((this.peak - 3) * (t - this.preinfusion)) / 2.5
        else
          pressure =
            this.peak * (1 - 0.18 * ((t - this.preinfusion - 2.5) / Math.max(this.duration - this.preinfusion - 2.5, 1)))
        this.status = {
          ...this.status,
          processActive: true,
          processKind: t < this.preinfusion ? 'infusion' : 'brew',
          processLabel: t < this.preinfusion ? 'Pre-infusion' : 'Extraction',
          pressure: Math.max(pressure + noise(0.15), 0),
          flow: t < this.preinfusion ? 3.5 - (t / this.preinfusion) * 1.5 : 1.8 + noise(0.2),
          temperature: target - 0.8 * Math.sin(Math.min(t / this.duration, 1) * Math.PI) + noise(0.1),
        }
      }
    } else {
      this.status = { ...this.status, temperature: target + noise(0.1) }
    }
    this.emit(this.status, true)
  }
}
