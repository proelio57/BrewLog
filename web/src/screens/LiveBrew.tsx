import { CircleCheck, Droplet, Gauge, Play, Scale, Square, TriangleAlert, X } from 'lucide-react'
import { useEffect, useRef } from 'react'
import { goBack, live, machine, navigate, pressure, repository, scale, settings, wakeLock, type BrewConfig } from '../app'
import type { BrewSession, BrewSnapshot } from '../brewing/brewSession'
import { useStore } from '../data/store'
import { fmt1, grams, grams1, mmss, newId, scaleReadout } from '../domain/format'
import { formatGrind, type Brew } from '../domain/models'
import { STEP_TITLES, isPour, stepHeadline, type RecipeStep } from '../domain/recipe'
import { BrewChart, MachineChart } from '../ui/chart'
import { Card, STEP_ICONS } from '../ui/components'

export function LiveBrew() {
  const active = live.brew
  useEffect(() => {
    if (!active) navigate('/brew', true)
  }, [active])
  if (!active) return null
  return <LiveBrewInner config={active.config} session={active.session} />
}

function LiveBrewInner({ config, session }: { config: BrewConfig; session: BrewSession }) {
  const snapshot = useStore(session.state)
  const scaleState = useStore(scale.state)
  const machineState = useStore(machine.state)
  const pressureState = useStore(pressure.state)
  const keepAwake = useStore(settings).keepAwake
  const espresso = session.isEspresso
  const showMachine = session.hasPressure || (espresso && machineState.connection === 'connected')

  const close = () => {
    session.discard()
    live.brew = null
    goBack()
  }

  const finishRef = useRef<() => void>(() => undefined)
  finishRef.current = () => {
    if (session.phase !== 'brewing') return
    session.finish()
    const brew: Brew = {
      id: newId(), date: Date.now(), recipeId: config.recipe.id, recipeName: config.recipe.name, recipe: config.recipe,
      dose: config.dose, targetWater: config.recipe.water, finalWeight: session.finalWeight, totalTime: session.elapsed,
      waterTemp: config.waterTemp, grindSetting: config.grindText, grindValue: config.grindValue, suggestedGrind: null,
      brewerId: config.brewer?.id ?? null, brewerName: config.brewer?.name ?? '',
      grinderId: config.grinder?.id ?? null, grinderName: config.grinder?.name ?? '', grinderSpec: config.grinder?.grinder ?? null,
      filterId: config.filter?.id ?? null, filterName: config.filter?.name ?? '', filterFlow: config.filter?.filterFlow ?? null,
      filterIdealRoast: config.filter?.idealRoast ?? null, beanId: config.beanId, usedScale: session.usesScale,
      rating: 0, feedback: [], notes: '', externalId: null,
    }
    repository.saveNewBrew(brew, session.usesScale ? session.recordedSamples() : [], session.recordedMachineSamples())
    live.brew = null
    navigate(`/brews/${brew.id}?new=1`, true)
  }

  useEffect(() => {
    session.onAutoFinish = () => finishRef.current()
    const unsubscribe = scale.onReading((grams, time) => session.ingest(grams, time))
    const detach = session.attach()
    const timer = setInterval(() => session.tick(), 50)
    return () => {
      unsubscribe()
      detach()
      clearInterval(timer)
    }
  }, [session])

  // GaggiMate refused to start because of a warning (e.g. low water): ask whether to start anyway.
  useEffect(() => {
    if (!machineState.startBlockedBy.length) return
    if (window.confirm(`GaggiMate didn't start the shot (${machineState.startBlockedBy.join(', ')}). Start anyway?`)) machine.startShot(true)
    else machine.dismissStartWarning()
  }, [machineState.startBlockedBy])

  useEffect(() => {
    if (keepAwake) void wakeLock.request()
    return () => wakeLock.release()
  }, [keepAwake])

  const confirmClose = () => {
    if (snapshot.phase !== 'brewing' || window.confirm('Discard this brew?')) close()
  }

  const scaleLive = snapshot.usesScale && (scaleState.isDemo || scaleState.connection === 'connected')
  const late = snapshot.phase === 'brewing' && snapshot.elapsed >= config.recipe.targetTime
  const first = config.recipe.steps[0]

  return (
    <div className="live">
      <div className="row">
        <button className="icon-btn filled" aria-label="Close" onClick={confirmClose}><X size={22} /></button>
        <div className="grow" style={{ textAlign: 'center' }}>
          <div className="title">{config.recipe.name}</div>
          <div className="small muted">{grams1(config.dose)} : {grams(config.recipe.water)} · {Math.round(config.waterTemp)} °C</div>
        </div>
        <span className="row" style={{ width: 40, justifyContent: 'center', gap: 4 }}>
          <span style={{ width: 8, height: 8, borderRadius: 4, background: scaleLive ? 'var(--good)' : 'var(--muted)' }} />
          <Scale size={16} />
        </span>
      </div>

      <div className="readouts">
        <div>
          <div className="readout-label">TIME</div>
          <div className="readout">{mmss(snapshot.elapsed)}</div>
          <div className="small" style={{ color: late ? 'var(--warn)' : 'var(--muted)' }}>target {mmss(config.recipe.targetTime)}</div>
        </div>
        <div style={{ textAlign: 'right' }}>
          <div className="readout-label">WEIGHT</div>
          {snapshot.usesScale ? (
            <>
              <div className="readout">{scaleReadout(snapshot.phase === 'preparing' ? snapshot.weight : Math.max(snapshot.weight, 0))}</div>
              <div className="small muted tnum">{fmt1(Math.max(snapshot.flowRate, 0))} g/s</div>
            </>
          ) : (
            <>
              <div className="readout">{snapshot.activeTarget != null ? `→${Math.trunc(snapshot.activeTarget)}` : '–'}</div>
              <div className="small muted">no scale</div>
            </>
          )}
        </div>
      </div>

      {showMachine && (
        <div className="row small tnum" style={{ fontWeight: 600, gap: 12 }}>
          <Gauge size={18} className="accent" />
          <span>{pressure.isReady ? `${fmt1(pressureState.pressure)} bar` : machineState.status.pressure != null ? `${fmt1(machineState.status.pressure)} bar` : '–'}</span>
          {machineState.connection === 'connected' && <>
            <span>{machineState.status.temperature != null ? `${fmt1(machineState.status.temperature)} °C` : '–'}</span>
            <span>{machineState.status.flow != null ? `${fmt1(machineState.status.flow)} ml/s` : '–'}</span>
          </>}
          <span className="grow" />
          <span className="tiny muted">{machineState.connection === 'connected' ? machine.displayName : pressure.displayName}</span>
        </div>
      )}

      {snapshot.phase === 'preparing' && (
        <Card>
          <div className="row">
            <Scale size={32} className="accent" />
            <div>
              <div className="title">{espresso ? 'Lock in the portafilter, cup on the scale' : 'Put the brewer with coffee on the scale'}</div>
              <div className="small muted">{preparingHint(session, snapshot.usesScale)}</div>
            </div>
          </div>
        </Card>
      )}
      {snapshot.phase === 'armed' && (
        <Card>
          <div className="row">
            <span style={{ position: 'relative', width: 56, height: 56, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <span className="pulse" style={{ position: 'absolute', inset: 0, borderRadius: 28, background: 'var(--accent-soft)' }} />
              <Droplet size={30} className="accent" fill="var(--accent)" />
            </span>
            <div>
              <div className="headline">{espresso ? (session.followsMachine ? 'Start the shot' : 'Ready for the shot') : snapshot.usesScale ? 'Start pouring' : 'Ready when you are'}</div>
              {first && <div className="small muted">{stepHeadline(first)}{first.note ? `. ${first.note}` : ''}</div>}
              {snapshot.usesScale && <div className="small accent" style={{ fontWeight: 600 }}>{snapshot.zeroConfirmed ? (session.followsMachine ? 'Timer starts with the pump' : 'Timer starts automatically') : 'Taring…'}</div>}
            </div>
          </div>
        </Card>
      )}
      {(snapshot.phase === 'brewing' || snapshot.phase === 'finished') && <ActiveStep snapshot={snapshot} session={session} />}

      {snapshot.phase === 'brewing' || snapshot.phase === 'finished'
        ? <>
          <BrewChart samples={snapshot.samples} recipe={config.recipe} currentTime={snapshot.elapsed} height={showMachine ? 120 : 160} />
          {session.hasPressure && <MachineChart samples={snapshot.machineSamples} targetPressure={config.recipe.pressure} currentTime={snapshot.elapsed} height={90} />}
        </>
        : <Preparation config={config} />}

      <div className="steps-strip">
        {config.recipe.steps.map((step, index) => {
          const brewing = snapshot.phase === 'brewing' || snapshot.phase === 'finished'
          const current = snapshot.currentStepIndex
          const done = brewing && current != null && index < current
          const isCurrent = brewing && current === index
          const Icon = done ? CircleCheck : STEP_ICONS[step.kind]
          return (
            <div key={index} className={`step-chip ${isCurrent ? 'current' : ''} ${done ? 'done' : ''}`}>
              <Icon size={18} color={done ? 'var(--good)' : isCurrent ? 'var(--accent)' : 'var(--muted)'} />
              <div>
                <div className="tiny muted tnum">{mmss(step.time)}</div>
                <div className="small" style={{ fontWeight: 600 }}>{isPour(step.kind) ? `${Math.trunc(step.target ?? 0)} g` : STEP_TITLES[step.kind]}</div>
              </div>
            </div>
          )
        })}
      </div>

      <div className="grow" />
      {snapshot.phase === 'preparing' && <button className="btn-primary" onClick={() => session.ready()}><CircleCheck size={20} />Ready</button>}
      {snapshot.phase === 'armed' && (espresso
        ? <button className="btn-primary" onClick={() => session.startShot()}><Play size={20} />{session.followsMachine ? `Start shot on ${machine.displayName}` : 'Start shot'}</button>
        : snapshot.usesScale
          ? <button className="link" style={{ alignSelf: 'center', padding: 12 }} onClick={() => session.startManually()}>Start timer manually</button>
          : <button className="btn-primary" onClick={() => session.startManually()}><Play size={20} />Start timer</button>)}
      {snapshot.phase === 'brewing' && (
        <button className="btn-primary green" onClick={() => finishRef.current()}><Square size={18} fill="#fff" />{espresso ? 'Stop · shot done' : 'Finish · drawdown done'}</button>
      )}
    </div>
  )
}

function ActiveStep({ snapshot, session }: { snapshot: BrewSnapshot; session: BrewSession }) {
  const recipe = session.recipe
  const current: RecipeStep | null = snapshot.currentStepIndex != null ? recipe.steps[snapshot.currentStepIndex] : null
  const next: RecipeStep | null = snapshot.nextStepIndex != null ? recipe.steps[snapshot.nextStepIndex] : null
  const flashColor = snapshot.flash === 'target' ? 'var(--good)' : snapshot.flash === 'nextStep' ? 'var(--accent)' : snapshot.flash === 'finish' ? 'var(--info)' : 'transparent'
  const target = snapshot.activeTarget
  const CurrentIcon = current ? STEP_ICONS[current.kind] : Droplet
  return (
    <Card className="flash" style={{ ['--flash' as string]: flashColor }}>
      <div className="row">
        <div className="grow" style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          {current && (
            <>
              <div className="row" style={{ gap: 6 }}><CurrentIcon size={22} /><span className="headline" style={{ fontSize: 20 }}>{stepHeadline(current)}</span></div>
              {current.valve && (
                <span className="badge" style={{ alignSelf: 'flex-start', color: current.valve === 'open' ? 'var(--good)' : 'var(--warn)',
                  background: current.valve === 'open' ? 'rgba(52,199,89,.16)' : 'rgba(255,149,0,.16)' }}>
                  {current.valve === 'open' ? 'Valve open' : 'Valve closed'}
                </span>
              )}
              {current.note && <div className="small muted">{current.note}</div>}
            </>
          )}
          {snapshot.usesScale && target != null && (
            <>
              <PourProgress weight={snapshot.weight} base={snapshot.activePourBase} target={target} pingAt={target - snapshot.pingLead} />
              {snapshot.overpour != null
                ? <span className="row small" style={{ color: 'var(--warn)', fontWeight: 600, gap: 4 }}><TriangleAlert size={16} />Over by {Math.trunc(snapshot.overpour)} g</span>
                : snapshot.weight >= target - snapshot.pingLead
                  ? <span className="row small" style={{ color: 'var(--good)', fontWeight: 600, gap: 4 }}><CircleCheck size={16} />Target reached, stop pouring</span>
                  : <span className="small muted tnum">{Math.trunc(target - snapshot.weight)} g to go</span>}
            </>
          )}
        </div>
        <CountdownRing progress={snapshot.countdownProgress} remaining={snapshot.timeToNextStep}
          overtime={next ? null : snapshot.elapsed - recipe.targetTime}
          label={next ? (isPour(next.kind) && next.target != null ? `→ ${Math.trunc(next.target)} g` : STEP_TITLES[next.kind]) : 'Drawdown'} />
      </div>
    </Card>
  )
}

function PourProgress({ weight, base, target, pingAt }: { weight: number; base: number; target: number; pingAt: number }) {
  const span = Math.max(target - base, 1)
  const fraction = Math.min(Math.max((weight - base) / span, 0), 1)
  const pingFraction = Math.min(Math.max((pingAt - base) / span, 0), 1)
  const color = weight > target + 2 ? 'var(--warn)' : weight >= pingAt ? 'var(--good)' : 'var(--accent)'
  return (
    <div className="progress" aria-label="Pour progress">
      <div className="fill" style={{ width: `${fraction * 100}%`, background: color }} />
      <div className="marker" style={{ left: `calc(${pingFraction * 100}% - 1px)` }} />
    </div>
  )
}

function CountdownRing({ progress, remaining, overtime, label }: { progress: number; remaining: number | null; overtime: number | null; label: string }) {
  const r = 40
  const c = 2 * Math.PI * r
  const color = remaining != null && remaining <= 5 ? 'var(--warn)' : 'var(--accent)'
  return (
    <div style={{ position: 'relative', width: 96, height: 96, flexShrink: 0 }}>
      <svg width={96} height={96} viewBox="0 0 96 96">
        <circle cx={48} cy={48} r={r} fill="none" stroke="var(--fill)" strokeWidth={8} />
        <circle cx={48} cy={48} r={r} fill="none" stroke={color} strokeWidth={8} strokeLinecap="round"
          strokeDasharray={`${c * progress} ${c}`} transform="rotate(-90 48 48)" />
      </svg>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
        {remaining != null && <span className="tnum" style={{ fontWeight: 700, fontSize: 20 }}>{mmss(Math.ceil(remaining))}</span>}
        {remaining == null && overtime != null && (
          <span className="tnum" style={{ fontWeight: 700, fontSize: 20, color: overtime >= 0 ? 'var(--warn)' : undefined }}>
            {overtime >= 0 ? `+${mmss(overtime)}` : mmss(Math.ceil(-overtime))}
          </span>
        )}
        <span className="tiny muted" style={{ fontWeight: 600 }}>{label}</span>
      </div>
    </div>
  )
}

function preparingHint(session: BrewSession, usesScale: boolean): string {
  if (session.isEspresso) {
    if (session.followsMachine) return 'Press Ready to tare. BrewLog follows the machine: the timer starts and stops with the pump.'
    return usesScale ? 'Press Ready to tare, then start the shot. The timer starts with the first drops or when you tap Start.'
      : 'No scale connected. Press Ready, then tap Start when you start the shot.'
  }
  return usesScale ? 'Press Ready to tare. The timer starts by itself when you start pouring.'
    : 'No scale connected. Press Ready, then start the timer when you pour.'
}

function Preparation({ config }: { config: BrewConfig }) {
  const grind = config.grindValue != null && config.grinder ? `, ground at ${formatGrind(config.grinder.grinder, config.grindValue)}`
    : config.grindText ? `, ground ${config.grindText}` : ''
  const items = config.recipe.method === 'espresso' ? [
    `Grind ${grams1(config.dose)} of coffee${grind}`,
    'Distribute (WDT) and tamp level',
    'Flush the group head, lock in the portafilter',
    `Brew at ${Math.round(config.waterTemp)} °C, stop at ${grams(config.recipe.water)}`,
  ] : [
    'Rinse the paper with hot water and discard it',
    `Add ${grams1(config.dose)} of coffee${grind}`,
    'Shake or swirl to level the bed',
    `Water at ${Math.round(config.waterTemp)} °C`,
  ]
  return (
    <Card>
      {items.map((text, i) => (
        <div className="row" key={i}>
          <span style={{ width: 22, height: 22, borderRadius: 11, background: 'var(--fill)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 11, fontWeight: 700 }}>{i + 1}</span>
          <span>{text}</span>
        </div>
      ))}
    </Card>
  )
}
