import { type AppSettings, DEFAULT_SETTINGS } from '../domain/models'
import { clamped } from '../domain/validation'
import { Store } from './store'

const KEY = 'brewlog.settings'

/** Settings in localStorage, parsed defensively with defaults. */
export function loadSettings(): AppSettings {
  let raw: Record<string, unknown> = {}
  try {
    const parsed = JSON.parse(localStorage.getItem(KEY) ?? '{}')
    if (parsed && typeof parsed === 'object') raw = parsed
  } catch {
    // Corrupt settings: fall back to defaults.
  }
  const d = DEFAULT_SETTINGS
  const bool = (key: keyof AppSettings) => (typeof raw[key] === 'boolean' ? (raw[key] as boolean) : (d[key] as boolean))
  const num = (key: keyof AppSettings, lo: number, hi: number) =>
    typeof raw[key] === 'number' ? clamped(raw[key] as number, lo, hi) : (d[key] as number)
  const str = (key: keyof AppSettings, maxLen = 200) =>
    typeof raw[key] === 'string' ? (raw[key] as string).slice(0, maxLen) : (d[key] as string)
  const validKinds: AppSettings['machineKind'][] = ['none', 'gaggimate', 'decent', 'laMarzocco', 'demo']
  const parsedKind = typeof raw.machineKind === 'string' ? (raw.machineKind as AppSettings['machineKind']) : 'none'
  return {
    autoStartThreshold: num('autoStartThreshold', 0.5, 5),
    pingLeadMode: raw.pingLeadMode === 'fixed' ? 'fixed' : 'auto',
    pingLeadGrams: num('pingLeadGrams', 0, 15),
    reactionTime: num('reactionTime', 0.2, 1.5),
    soundEnabled: bool('soundEnabled'),
    hapticsEnabled: bool('hapticsEnabled'),
    soundVolume: num('soundVolume', 0.1, 1),
    silentModeSound: bool('silentModeSound'),
    countdownTicks: bool('countdownTicks'),
    weighBeansFirst: bool('weighBeansFirst'),
    rinsePaper: bool('rinsePaper'),
    finishPing: bool('finishPing'),
    keepAwake: bool('keepAwake'),
    onboardingDone: bool('onboardingDone'),
    setupBannerDismissed: bool('setupBannerDismissed'),
    quickWeighAutoStart: bool('quickWeighAutoStart'),
    chartShowsFlow: bool('chartShowsFlow'),
    demoScale: bool('demoScale'),
    onlineRecipes: bool('onlineRecipes'),
    machineKind: validKinds.includes(parsedKind) ? parsedKind : 'none',
    machineHost: typeof raw.machineHost === 'string' && raw.machineHost.length <= 253 ? raw.machineHost : d.machineHost,
    pressureEnabled: bool('pressureEnabled'),
    pressureDemo: bool('pressureDemo'),
    brewMode: raw.brewMode === 'espresso' ? 'espresso' : 'filter',
    autoStopShot: bool('autoStopShot'),
    shotStopLag: num('shotStopLag', 0.5, 2.5),
    voicePrompts: bool('voicePrompts'),
    voiceAnnounceAhead: bool('voiceAnnounceAhead'),
    valveCountdown: bool('valveCountdown'),
    decentDeviceId: str('decentDeviceId', 100),
    laMarzoccoUser: str('laMarzoccoUser', 200),
    laMarzoccoPassword: str('laMarzoccoPassword', 200),
    laMarzoccoSerial: str('laMarzoccoSerial', 100),
  }
}

export class SettingsStore extends Store<AppSettings> {
  constructor() {
    super(loadSettings())
  }

  change(transform: (settings: AppSettings) => AppSettings): void {
    this.update(transform)
    try {
      localStorage.setItem(KEY, JSON.stringify(this.get()))
    } catch {
      // Storage full or blocked: keep the in-memory value.
    }
  }
}
