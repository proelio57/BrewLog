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
    finishPing: bool('finishPing'),
    keepAwake: bool('keepAwake'),
    onboardingDone: bool('onboardingDone'),
    setupBannerDismissed: bool('setupBannerDismissed'),
    quickWeighAutoStart: bool('quickWeighAutoStart'),
    chartShowsFlow: bool('chartShowsFlow'),
    demoScale: bool('demoScale'),
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
