import type { MachineMode, MachineStatus } from '../domain/models'

export const DECENT_SERVICE_UUID = '0000a000-0000-1000-8000-00805f9b34fb'
export const DECENT_REQUESTED_STATE_UUID = '0000a002-0000-1000-8000-00805f9b34fb'
export const DECENT_SHOT_SAMPLE_UUID = '0000a00d-0000-1000-8000-00805f9b34fb'
export const DECENT_STATE_INFO_UUID = '0000a00e-0000-1000-8000-00805f9b34fb'

export enum DecentState {
  SLEEP = 0,
  GOING_TO_SLEEP = 1,
  IDLE = 2,
  BUSY = 3,
  ESPRESSO = 4,
  STEAM = 5,
  HOT_WATER = 6,
  SHORT_CAL = 7,
  SELF_TEST = 8,
  LONG_CAL = 9,
  DESCALE = 10,
  FATAL_ERROR = 11,
  INITIALIZING = 12,
  NO_REQUEST = 13,
  SKIP_TO_NEXT = 14,
  HOT_WATER_RINSE = 15,
  STEAM_RINSE = 16,
  REFILL = 17,
  CLEAN = 18,
  IN_BOOT_LOADER = 19,
  AIR_PURGE = 20,
  SCHED_IDLE = 21,
}

export enum DecentSubstate {
  NONE = 0,
  HEAT_WATER_TANK = 1,
  HEAT_WATER_HEATER = 2,
  STABILIZE_MIX_TEMP = 3,
  PRE_INFUSE = 4,
  POUR = 5,
  FLUSH = 6,
  STEAMING = 7,
}

export interface DecentShotSample {
  pressure: number
  flow: number
  mixTemp: number
  headTemp: number
  targetMixTemp: number
  targetHeadTemp: number
  targetPressure: number
  targetFlow: number
  frame: number
}

export interface DecentStateResult {
  state: number
  substate: number
}

function errorMessage(substate: number, state: number): string {
  switch (substate) {
    case 204:
      return 'Temperature sensor error'
    case 205:
      return 'Pressure sensor error'
    case 206:
      return 'Water level error'
    default:
      return substate >= 200 ? `Machine error ${substate}` : `Machine error (state ${state})`
  }
}

export const DecentProtocol = {
  sample(data: Uint8Array): DecentShotSample | null {
    if (data.length < 19) return null
    const u16 = (i: number) => ((data[i] & 0xff) << 8) | (data[i + 1] & 0xff)
    const u24 = (i: number) => ((data[i] & 0xff) << 16) | ((data[i + 1] & 0xff) << 8) | (data[i + 2] & 0xff)
    return {
      pressure: u16(2) / 4096.0,
      flow: u16(4) / 4096.0,
      mixTemp: u16(6) / 256.0,
      headTemp: u24(8) / 65536.0,
      targetMixTemp: u16(11) / 256.0,
      targetHeadTemp: u16(13) / 256.0,
      targetPressure: (data[15] & 0xff) / 16.0,
      targetFlow: (data[16] & 0xff) / 16.0,
      frame: data[17] & 0xff,
    }
  },

  state(data: Uint8Array): DecentStateResult | null {
    if (data.length < 2) return null
    return { state: data[0] & 0xff, substate: data[1] & 0xff }
  },

  apply(
    sampleOrRawState: DecentShotSample | number,
    statusOrSubstate: MachineStatus | number,
    maybeStatus?: MachineStatus,
  ): MachineStatus {
    if (typeof sampleOrRawState === 'object') {
      const sample = sampleOrRawState
      const status = statusOrSubstate as MachineStatus
      return {
        ...status,
        pressure: Math.min(Math.max(sample.pressure, 0.0), 20.0),
        flow: Math.min(Math.max(sample.flow, 0.0), 30.0),
        temperature: Math.min(Math.max(sample.headTemp, 0.0), 200.0),
        targetTemperature: sample.targetHeadTemp > 0 ? Math.min(sample.targetHeadTemp, 200.0) : null,
        targetPressure: sample.targetPressure > 0 ? sample.targetPressure : null,
        hasPressure: true,
      }
    }

    const rawState = sampleOrRawState
    const substate = statusOrSubstate as number
    const status = maybeStatus ?? {
      connected: true,
      online: true,
      temperature: null,
      targetTemperature: null,
      pressure: null,
      targetPressure: null,
      flow: null,
      weight: null,
      mode: null,
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
      deviceKind: 'decent',
    }

    let next = { ...status }
    switch (rawState) {
      case DecentState.SLEEP:
      case DecentState.GOING_TO_SLEEP:
      case DecentState.SCHED_IDLE:
        next.mode = 0 // standby
        break
      case DecentState.STEAM:
      case DecentState.STEAM_RINSE:
        next.mode = 2 // steam
        break
      case DecentState.HOT_WATER:
      case DecentState.HOT_WATER_RINSE:
        next.mode = 3 // water
        break
      case DecentState.IDLE:
      case DecentState.ESPRESSO:
      case DecentState.BUSY:
        next.mode = 1 // brew
        break
    }

    if (substate >= 200 || rawState === DecentState.FATAL_ERROR) {
      return {
        ...next,
        systemState: 'error',
        systemMessage: errorMessage(substate, rawState),
        processActive: false,
        processKind: null,
        processLabel: null,
        processIsUtility: false,
      }
    }

    next = {
      ...next,
      systemState: rawState === DecentState.SLEEP ? 'sleep' : 'ready',
      systemMessage: null,
    }

    if (rawState === DecentState.ESPRESSO && substate === DecentSubstate.PRE_INFUSE) {
      return { ...next, processActive: true, processKind: 'infusion', processLabel: 'Pre-infusion', processIsUtility: false }
    }
    if (rawState === DecentState.ESPRESSO && substate === DecentSubstate.POUR) {
      return { ...next, processActive: true, processKind: 'brew', processLabel: 'Extraction', processIsUtility: false }
    }
    const utilityStates = [
      DecentState.HOT_WATER_RINSE,
      DecentState.HOT_WATER,
      DecentState.STEAM,
      DecentState.STEAM_RINSE,
      DecentState.CLEAN,
      DecentState.DESCALE,
    ]
    if (utilityStates.includes(rawState)) {
      const runningSubstates = [
        DecentSubstate.POUR,
        DecentSubstate.FLUSH,
        DecentSubstate.STEAMING,
        DecentSubstate.PRE_INFUSE,
      ]
      const running = runningSubstates.includes(substate)
      return {
        ...next,
        processActive: running,
        processKind: running ? 'brew' : null,
        processLabel: running ? 'Flush' : null,
        processIsUtility: true,
      }
    }

    return {
      ...next,
      processActive: false,
      processKind: null,
      processLabel: null,
      processIsUtility: false,
    }
  },

  command(mode: MachineMode): Uint8Array {
    switch (mode) {
      case 'standby':
        return Uint8Array.from([DecentState.SLEEP])
      case 'brew':
      case 'grind':
        return Uint8Array.from([DecentState.IDLE])
      case 'steam':
        return Uint8Array.from([DecentState.STEAM])
      case 'water':
        return Uint8Array.from([DecentState.HOT_WATER])
    }
  },

  get startShot(): Uint8Array {
    return Uint8Array.from([DecentState.ESPRESSO])
  },

  get stopShot(): Uint8Array {
    return Uint8Array.from([DecentState.IDLE])
  },
}

/** Web Bluetooth driver for Decent DE1. */
export class DecentConnection {
  private device: BluetoothDevice | null = null
  private requestedStateChar: BluetoothRemoteGATTCharacteristic | null = null
  private shotSampleChar: BluetoothRemoteGATTCharacteristic | null = null
  private stateInfoChar: BluetoothRemoteGATTCharacteristic | null = null
  onStatus?: (status: MachineStatus, isTelemetry: boolean) => void
  onDisconnect?: () => void
  private status: MachineStatus = {
    connected: false,
    online: false,
    temperature: null,
    targetTemperature: null,
    pressure: null,
    targetPressure: null,
    flow: null,
    weight: null,
    mode: 1,
    profile: null,
    hasPressure: true,
    processActive: false,
    processKind: null,
    processLabel: null,
    processIsUtility: false,
    scaleConnected: false,
    systemState: 'ready',
    systemMessage: null,
    capabilities: ['startStop'],
    deviceKind: 'decent',
    deviceName: 'Decent DE1',
  }

  get isConnected(): boolean {
    return this.device?.gatt?.connected ?? false
  }

  async connect(_deviceId?: string): Promise<void> {
    if (typeof navigator === 'undefined' || !navigator.bluetooth) {
      throw new Error('Web Bluetooth is not supported in this browser.')
    }

    try {
      const options: RequestDeviceOptions = {
        filters: [{ namePrefix: 'DE1' }, { services: [DECENT_SERVICE_UUID] }],
        optionalServices: [DECENT_SERVICE_UUID],
      }
      const device = await navigator.bluetooth.requestDevice(options)
      this.device = device
      device.addEventListener('gattserverdisconnected', () => {
        this.status = { ...this.status, connected: false, online: false }
        this.onDisconnect?.()
      })

      const server = await device.gatt?.connect()
      if (!server) throw new Error('Could not connect to DE1 GATT server.')
      const service = await server.getPrimaryService(DECENT_SERVICE_UUID)

      this.requestedStateChar = await service.getCharacteristic(DECENT_REQUESTED_STATE_UUID)
      this.shotSampleChar = await service.getCharacteristic(DECENT_SHOT_SAMPLE_UUID)
      this.stateInfoChar = await service.getCharacteristic(DECENT_STATE_INFO_UUID)

      await this.shotSampleChar.startNotifications()
      this.shotSampleChar.addEventListener('characteristicvaluechanged', (e: Event) => {
        const char = e.target as BluetoothRemoteGATTCharacteristic
        if (!char.value) return
        const buf = new Uint8Array(char.value.buffer, char.value.byteOffset, char.value.byteLength)
        const sample = DecentProtocol.sample(buf)
        if (sample) {
          this.status = DecentProtocol.apply(sample, this.status)
          this.onStatus?.(this.status, true)
        }
      })

      await this.stateInfoChar.startNotifications()
      this.stateInfoChar.addEventListener('characteristicvaluechanged', (e: Event) => {
        const char = e.target as BluetoothRemoteGATTCharacteristic
        if (!char.value) return
        const buf = new Uint8Array(char.value.buffer, char.value.byteOffset, char.value.byteLength)
        const st = DecentProtocol.state(buf)
        if (st) {
          this.status = DecentProtocol.apply(st.state, st.substate, this.status)
          this.onStatus?.(this.status, false)
        }
      })

      this.status = { ...this.status, connected: true, online: true, deviceName: device.name || 'Decent DE1' }
      this.onStatus?.(this.status, false)
    } catch (err) {
      this.status = { ...this.status, connected: false, online: false }
      throw err
    }
  }

  disconnect(): void {
    if (this.device?.gatt?.connected) {
      this.device.gatt.disconnect()
    }
    this.device = null
    this.status = { ...this.status, connected: false, online: false }
  }

  async sendCommand(command: Uint8Array): Promise<void> {
    if (!this.requestedStateChar) throw new Error('DE1 not connected.')
    await this.requestedStateChar.writeValueWithResponse(command.buffer as ArrayBuffer)
  }

  async startShot(): Promise<void> {
    await this.sendCommand(DecentProtocol.startShot)
  }

  async stopShot(): Promise<void> {
    await this.sendCommand(DecentProtocol.stopShot)
  }
}
