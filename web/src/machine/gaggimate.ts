import { roundHalfAway } from '../domain/format'
import { scaled, type Recipe } from '../domain/recipe'

// Port of MachineStatus.swift: GaggiMate's WebSocket protocol (docs/websocket-api.yaml in jniebuhr/gaggimate).

/** Live state of a GaggiMate controller, merged from its partial `evt:status` frames. */
export interface GaggiMateStatus {
  temperature: number | null
  targetTemperature: number | null
  pressure: number | null
  targetPressure: number | null
  flow: number | null
  /** 0 standby, 1 brew, 2 steam, 3 water, 4 grind. */
  mode: number | null
  profile: string | null
  hasPressure: boolean | null
  processActive: boolean
  /** "brew", "infusion" or "grind". */
  processKind: string | null
  processLabel: string | null
  processIsUtility: boolean
  /** Weight from the scale connected to GaggiMate. */
  weight: number | null
  scaleConnected: boolean
  systemState: string | null
  systemMessage: string | null
}

export const emptyStatus = (): GaggiMateStatus => ({
  temperature: null, targetTemperature: null, pressure: null, targetPressure: null, flow: null, mode: null, profile: null,
  hasPressure: null, processActive: false, processKind: null, processLabel: null, processIsUtility: false, weight: null,
  scaleConnected: false, systemState: null, systemMessage: null,
})

/** A shot is running (pre-infusion or extraction), not a flush or grind. */
export const isBrewing = (s: GaggiMateStatus): boolean =>
  s.processActive && !s.processIsUtility && (s.processKind === 'brew' || s.processKind === 'infusion')

export const hasWeight = (s: GaggiMateStatus): boolean => s.scaleConnected && s.weight != null

type Frame = Record<string, unknown>
const isObj = (v: unknown): v is Frame => typeof v === 'object' && v !== null && !Array.isArray(v)

/** Parses a WebSocket text message. Returns the frame if it's an `evt:status`. */
export function statusFrame(text: string): Frame | null {
  if (text.length > 64 * 1024) return null
  try {
    const value = JSON.parse(text) as unknown
    return isObj(value) && value.tp === 'evt:status' ? value : null
  } catch {
    return null
  }
}

/** True if the frame carries live readings (as opposed to the slow state). */
export const isTelemetry = (frame: Frame): boolean => 'pr' in frame || 'ct' in frame

/** Missing keys keep their value, null clears it. Numbers are clamped to sane ranges. */
export function mergeStatus(status: GaggiMateStatus, frame: Frame): GaggiMateStatus {
  const next = { ...status }
  const number = (key: string, field: 'temperature' | 'targetTemperature' | 'pressure' | 'targetPressure' | 'flow' | 'weight', lo: number, hi: number) => {
    if (!(key in frame)) return
    const v = frame[key]
    next[field] = typeof v === 'number' && Number.isFinite(v) ? Math.min(Math.max(v, lo), hi) : null
  }
  number('ct', 'temperature', 0, 200)
  number('tt', 'targetTemperature', 0, 200)
  number('pr', 'pressure', 0, 20)
  number('pt', 'targetPressure', 0, 20)
  number('fl', 'flow', 0, 30)
  number('cw', 'weight', -100, 5000)
  if ('m' in frame) next.mode = typeof frame.m === 'number' ? Math.trunc(frame.m) : null
  if ('p' in frame) next.profile = typeof frame.p === 'string' ? frame.p.slice(0, 80) : null
  if ('cp' in frame) next.hasPressure = typeof frame.cp === 'boolean' ? frame.cp : null
  if ('bc' in frame) next.scaleConnected = frame.bc === true
  if (isObj(frame.sys)) {
    next.systemState = typeof frame.sys.s === 'string' ? frame.sys.s.slice(0, 20) : null
    next.systemMessage = typeof frame.sys.m === 'string' ? frame.sys.m.slice(0, 200) : null
  }
  if ('process' in frame) {
    const process = frame.process
    if (isObj(process)) {
      next.processActive = process.a === 1
      next.processKind = typeof process.s === 'string' ? process.s : null
      next.processLabel = typeof process.l === 'string' ? process.l.slice(0, 80) : null
      next.processIsUtility = process.u === 1
    } else {
      next.processActive = false
      next.processKind = null
      next.processLabel = null
      next.processIsUtility = false
    }
  }
  return next
}

/** "gaggimate.local", "192.168.1.20", "http://gaggimate.local/" → ws URL; null for anything else. */
export function gaggiMateUrl(input: string): string | null {
  let host = input.trim().toLowerCase()
  for (const prefix of ['http://', 'https://', 'ws://', 'wss://']) if (host.startsWith(prefix)) host = host.slice(prefix.length)
  while (host.endsWith('/')) host = host.slice(0, -1)
  if (host.endsWith('/ws')) host = host.slice(0, -3)
  if (!host || host.length > 253 || !/^[a-z0-9.\-:]+$/.test(host)) return null
  return `ws://${host}/ws`
}

export const MACHINE_MODES = [
  { mode: 0, title: 'Standby' }, { mode: 1, title: 'Brew' }, { mode: 2, title: 'Steam' }, { mode: 3, title: 'Water' },
] as const

export const PROFILE_LABEL_PREFIX = 'BrewLog · '

/** Builds a GaggiMate profile (schema/profile.json in the GaggiMate repo) from an espresso recipe. */
export function makeProfile(recipe: Recipe, dose: number, temperature: number, hasPressure: boolean, hasScale: boolean): Record<string, unknown> {
  const yieldGrams = roundHalfAway(scaled(recipe, dose).water)
  const extractStart = recipe.steps.find((s) => s.kind === 'extract')?.time ?? 0
  const preinfusion = hasPressure ? roundHalfAway(Math.max(extractStart - 2, 0)) : 0
  const pressure = Math.min(Math.max(recipe.pressure ?? 9, 1), 12)
  const phases: Record<string, unknown>[] = []
  if (preinfusion >= 1) {
    phases.push({ name: 'Pre-infusion', phase: 'preinfusion', valve: 1, duration: preinfusion, pump: { target: 'pressure', pressure: 3, flow: 4 } })
  }
  const brew: Record<string, unknown> = {
    name: 'Extraction', phase: 'brew', valve: 1,
    // With a scale the weight ends the shot and the duration is only a safety cap.
    duration: hasScale ? roundHalfAway(recipe.targetTime + 20) : roundHalfAway(Math.max(recipe.targetTime - preinfusion, 5)),
    pump: hasPressure ? { target: 'pressure', pressure, flow: 0 } : 100,
  }
  if (hasPressure) brew.transition = { type: 'linear', duration: 2, adaptive: true }
  if (hasScale) brew.targets = [{ type: 'volumetric', operator: 'gte', value: yieldGrams }]
  phases.push(brew)
  return {
    label: (PROFILE_LABEL_PREFIX + recipe.name).slice(0, 60),
    type: 'pro',
    description: `From BrewLog: ${dose.toFixed(1)} g in, ${yieldGrams.toFixed(0)} g out, about ${recipe.targetTime.toFixed(0)} s.`,
    temperature: Math.min(Math.max(roundHalfAway(temperature), 80), 100),
    dose: Math.min(Math.max(dose, 1), 100),
    phases,
  }
}
