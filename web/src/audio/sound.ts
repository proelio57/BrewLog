import type { BrewCue } from '../brewing/brewSession'
import type { AppSettings } from '../domain/models'

interface Note { frequency: number; delay: number; gain: number }

const CUES: Record<BrewCue, { notes: Note[]; decay: number; duration: number }> = {
  // E6: single, short, soft ping
  target: { notes: [{ frequency: 1318.5, delay: 0, gain: 0.9 }], decay: 9, duration: 0.55 },
  // A5 → E6 rising chime
  nextStep: { notes: [{ frequency: 880, delay: 0, gain: 0.8 }, { frequency: 1318.5, delay: 0.13, gain: 0.7 }], decay: 5, duration: 1.3 },
  // C6 → G5 → E5 calm, descending
  finish: {
    notes: [{ frequency: 1046.5, delay: 0, gain: 0.7 }, { frequency: 784, delay: 0.2, gain: 0.7 }, { frequency: 659.3, delay: 0.4, gain: 0.8 }],
    decay: 3.5, duration: 2,
  },
  tick: { notes: [{ frequency: 1760, delay: 0, gain: 0.35 }], decay: 35, duration: 0.12 },
}

const VIBRATION: Record<BrewCue, number | number[]> = { target: 20, tick: 10, nextStep: [30, 60, 30], finish: [40, 80, 40] }

/**
 * Synthesizes soft bell-like cues with Web Audio (same synthesis as iOS/Android: a fundamental with quickly
 * decaying partials, soft attack, exponential decay). Browsers only allow audio after a user gesture, so
 * [unlock] is called on the first tap.
 */
export class SoundPlayer {
  private context: AudioContext | null = null
  private buffers = new Map<BrewCue, AudioBuffer>()

  constructor(private readonly settings: () => AppSettings) {}

  unlock(): void {
    try {
      // iOS 17+: play even when the ring/silent switch is set to silent.
      const session = (navigator as Navigator & { audioSession?: { type: string } }).audioSession
      if (session) session.type = this.settings().silentModeSound ? 'playback' : 'ambient'
      if (!this.context) {
        const Context = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
        if (!Context) return
        this.context = new Context()
      }
      if (this.context.state === 'suspended') void this.context.resume()
    } catch {
      // Audio unavailable: cues are silent.
    }
  }

  cue(cue: BrewCue): void {
    const s = this.settings()
    if (s.soundEnabled) this.play(cue)
    if (s.hapticsEnabled && 'vibrate' in navigator) {
      try {
        navigator.vibrate(VIBRATION[cue])
      } catch {
        // ignore
      }
    }
  }

  private play(cue: BrewCue): void {
    this.unlock()
    const context = this.context
    if (!context) return
    const buffer = this.buffers.get(cue) ?? this.render(context, cue)
    this.buffers.set(cue, buffer)
    const source = context.createBufferSource()
    const gain = context.createGain()
    gain.gain.value = this.settings().soundVolume
    source.buffer = buffer
    source.connect(gain).connect(context.destination)
    source.start()
  }

  private render(context: AudioContext, cue: BrewCue): AudioBuffer {
    const { notes, decay, duration } = CUES[cue]
    const rate = context.sampleRate
    const frames = Math.floor(duration * rate)
    const fadeOut = Math.floor(0.03 * rate)
    const buffer = context.createBuffer(1, frames, rate)
    const channel = buffer.getChannelData(0)
    for (let i = 0; i < frames; i++) {
      const t = i / rate
      let sample = 0
      for (const note of notes) {
        if (t < note.delay) continue
        const lt = t - note.delay
        const envelope = Math.min(1, lt / 0.008) * Math.exp(-lt * decay)
        const w = 2 * Math.PI * note.frequency * lt
        sample += note.gain * envelope *
          (Math.sin(w) + 0.3 * Math.exp(-lt * decay * 0.8) * Math.sin(2 * w) + 0.1 * Math.exp(-lt * decay * 1.6) * Math.sin(3.01 * w))
      }
      let value = sample * 0.32
      const remaining = frames - i
      if (remaining < fadeOut) value *= remaining / fadeOut
      channel[i] = value
    }
    return buffer
  }
}

/** Keeps the screen on while brewing (Screen Wake Lock API). */
export class WakeLock {
  private lock: WakeLockSentinel | null = null
  private wanted = false

  constructor() {
    document.addEventListener('visibilitychange', () => {
      if (this.wanted && document.visibilityState === 'visible') void this.acquire()
    })
  }

  async request(): Promise<void> {
    this.wanted = true
    await this.acquire()
  }

  release(): void {
    this.wanted = false
    void this.lock?.release().catch(() => undefined)
    this.lock = null
  }

  private async acquire(): Promise<void> {
    try {
      if ('wakeLock' in navigator && !this.lock) {
        this.lock = await navigator.wakeLock.request('screen')
        this.lock.addEventListener('release', () => {
          this.lock = null
        })
      }
    } catch {
      // Not supported or denied: the screen may dim.
    }
  }
}
