import { ArrowDownToLine, Pause, Play, RotateCcw, Scale, X, type LucideIcon } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { goBack, scale, settings, wakeLock } from '../app'
import { MAX_RECENT_READINGS, slope } from '../brewing/brewSession'
import { useStore } from '../data/store'
import { fmt1, mmss, scaleReadout } from '../domain/format'
import type { WeightSample } from '../domain/models'
import { monotonicMillis } from '../scale/scaleManager'
import { BrewChart } from '../ui/chart'
import { Card, Toggle } from '../ui/components'
import { ScaleSheet } from './BrewSetup'

/** "Just weigh": a plain scale + timer, with no recipe and nothing saved. Port of QuickWeighModel. */
class QuickWeighModel {
  weight = 0
  flow = 0
  elapsed = 0
  isRunning = false
  /** Waiting for the first pour after a tare (auto-start). */
  isArmed = false
  samples: WeightSample[] = []
  autoStart = true
  private startMs: number | null = null
  private accumulated = 0
  private recent: [number, number][] = []
  private awaitingZero = false
  private lastSampleT = -1

  tare(): void {
    scale.tare()
    this.reset()
    // Arm only once the scale reports ~0 g, so the pre-tare weight can't trigger a start.
    this.awaitingZero = true
  }

  toggle(): void {
    if (this.isRunning) this.pause()
    else this.start()
  }

  reset(): void {
    this.pause()
    this.accumulated = 0
    this.elapsed = 0
    this.samples = []
    this.lastSampleT = -1
    this.isArmed = false
  }

  tick(): void {
    this.elapsed = this.accumulated + (this.startMs != null ? (monotonicMillis() - this.startMs) / 1000 : 0)
  }

  ingest(grams: number, atMs: number): void {
    if (!Number.isFinite(grams)) return
    this.weight = grams
    this.recent.push([atMs, grams])
    while (this.recent.length && atMs - this.recent[0][0] > 3_000) this.recent.shift()
    while (this.recent.length > MAX_RECENT_READINGS) this.recent.shift()
    this.flow = slope(this.recent, 1.2, atMs)
    if (this.awaitingZero && Math.abs(grams) < 1) {
      this.awaitingZero = false
      this.isArmed = this.autoStart
    }
    if (this.isArmed && !this.isRunning && grams >= settings.get().autoStartThreshold) this.start()
    if (this.isRunning) {
      const t = this.accumulated + (this.startMs != null ? (atMs - this.startMs) / 1000 : 0)
      if (t - this.lastSampleT >= 0.2 && this.samples.length < 9_000) {
        this.samples = [...this.samples, { t, w: grams }]
        this.lastSampleT = t
      }
    }
  }

  private start(): void {
    this.startMs = monotonicMillis()
    this.isRunning = true
    this.isArmed = false
  }

  private pause(): void {
    if (this.startMs != null) this.accumulated += (monotonicMillis() - this.startMs) / 1000
    this.startMs = null
    this.isRunning = false
  }
}

export function QuickWeigh() {
  const appSettings = useStore(settings)
  const scaleState = useStore(scale.state)
  const model = useRef(new QuickWeighModel()).current
  const [, setFrame] = useState(0)
  const [showScale, setShowScale] = useState(false)
  model.autoStart = appSettings.quickWeighAutoStart
  const ready = scaleState.isDemo || scaleState.connection === 'connected'

  useEffect(() => {
    model.weight = scale.state.get().weight
    const unsubscribe = scale.onReading((grams, time) => model.ingest(grams, time))
    const timer = setInterval(() => {
      model.tick()
      setFrame((f) => f + 1)
    }, 100)
    return () => {
      unsubscribe()
      clearInterval(timer)
    }
  }, [model])

  useEffect(() => {
    if (appSettings.keepAwake) void wakeLock.request()
    return () => wakeLock.release()
  }, [appSettings.keepAwake])

  const hint = model.isRunning ? 'Timer running'
    : model.isArmed ? 'Start pouring, the timer starts automatically'
      : model.autoStart ? 'Tare, then pour. The timer starts by itself' : 'Press Start when you pour'

  return (
    <div className="live" style={{ alignItems: 'center' }}>
      <div className="row" style={{ width: '100%' }}>
        <button className="icon-btn filled" aria-label="Close" onClick={() => goBack()}><X size={22} /></button>
        <div className="grow title" style={{ textAlign: 'center' }}>Quick weigh</div>
        <button className="row" style={{ width: 40, justifyContent: 'center', gap: 4 }} aria-label="Scale connection" onClick={() => setShowScale(true)}>
          <span style={{ width: 8, height: 8, borderRadius: 4, background: ready ? 'var(--good)' : 'var(--muted)' }} />
          <Scale size={16} />
        </button>
      </div>
      {!ready && (
        <Card style={{ width: '100%' }}>
          <div className="row">
            <Scale className="muted" />
            <div className="grow"><div className="title">No scale connected</div><div className="small muted">Connect your BOOKOO or turn on the demo scale.</div></div>
            <button className="btn tinted" onClick={() => setShowScale(true)}>Connect</button>
          </div>
        </Card>
      )}
      <div style={{ textAlign: 'center' }}>
        <div className="tnum" style={{ fontSize: 88, fontWeight: 600, lineHeight: 1 }}>{scaleReadout(model.weight)}</div>
        <div className="muted">grams · {fmt1(Math.max(model.flow, 0))} g/s</div>
      </div>
      <div style={{ textAlign: 'center' }}>
        <div className="tnum" style={{ fontSize: 44, fontWeight: 500 }}>{mmss(model.elapsed)}</div>
        <div className="small" style={{ fontWeight: 600, color: model.isArmed ? 'var(--accent)' : 'var(--muted)' }}>{hint}</div>
      </div>
      <div className="row" style={{ gap: 18 }}>
        <RoundButton label="Tare" icon={ArrowDownToLine} onClick={() => model.tare()} />
        <RoundButton label={model.isRunning ? 'Pause' : 'Start'} icon={model.isRunning ? Pause : Play} prominent onClick={() => model.toggle()} />
        <RoundButton label="Reset" icon={RotateCcw} onClick={() => model.reset()} />
      </div>
      <div style={{ width: '100%' }}>
        <Toggle label="Start the timer when I start pouring" checked={appSettings.quickWeighAutoStart}
          onChange={(v) => settings.change((s) => ({ ...s, quickWeighAutoStart: v }))} />
      </div>
      {model.samples.length > 2 && (
        <div style={{ width: '100%' }}><BrewChart samples={model.samples} recipe={null} currentTime={model.isRunning ? model.elapsed : null} height={160} /></div>
      )}
      {showScale && <ScaleSheet onClose={() => setShowScale(false)} />}
    </div>
  )
}

function RoundButton({ label, icon: Icon, prominent, onClick }: { label: string; icon: LucideIcon; prominent?: boolean; onClick: () => void }) {
  return (
    <button className="step-btn" onClick={onClick} style={{ fontSize: 12, fontWeight: 600 }}>
      <span className="circle" style={{ width: 72, height: 72, borderRadius: 36, background: prominent ? 'var(--accent)' : 'var(--fill)', color: prominent ? '#fff' : 'var(--text)' }}>
        <Icon size={30} />
      </span>
      {label}
    </button>
  )
}
