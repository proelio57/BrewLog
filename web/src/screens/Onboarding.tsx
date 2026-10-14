import { ChartLine, Check, ChevronLeft, Circle, CircleCheck, Coffee, Droplet, FileText, Gauge, Leaf, Scale, SlidersHorizontal, Sparkles, type LucideIcon } from 'lucide-react'
import { useState } from 'react'
import { navigate, repository, scale, settings, setup } from '../app'
import { useStore } from '../data/store'
import { BREWER_PRESETS, FILTER_PRESETS, GRINDER_PRESETS, makeEquipment, specFor, type EquipmentPreset } from '../domain/library'
import { FLOW_NAMES, GRIND_UNIT_NAMES, ROAST_LEVELS, ROAST_NAMES, formatGrind, newBean, type Equipment, type GrindUnit, type RoastLevel } from '../domain/models'
import { METHOD_NAMES } from '../domain/recipe'
import { LIMITS, sanitized } from '../domain/validation'
import { Card, Chip, SectionHeader, TextInput, Toggle } from '../ui/components'
import { GrindInput, ScaleCard, ScaleSheet } from './BrewSetup'

type Step = 'welcome' | 'brewer' | 'filter' | 'grinder' | 'beans' | 'scale' | 'done'
const STEPS: Step[] = ['welcome', 'brewer', 'filter', 'grinder', 'beans', 'scale', 'done']
const QUESTIONS: Step[] = ['brewer', 'filter', 'grinder', 'beans', 'scale']
const CUSTOM = '__custom__'

/** First-launch setup assistant: brewer → filter → grinder → beans → scale. Every step is optional. */
export function Onboarding() {
  const [step, setStep] = useState<Step>('welcome')
  const [brewers, setBrewers] = useState<string[]>([])
  const [filters, setFilters] = useState<string[]>([])
  const [grinder, setGrinder] = useState<string | null>(null)
  const [customName, setCustomName] = useState('')
  const [customUnit, setCustomUnit] = useState<GrindUnit>('clicks')
  const [grindValue, setGrindValue] = useState<number | null>(null)
  const [beanName, setBeanName] = useState('')
  const [roaster, setRoaster] = useState('')
  const [roastLevel, setRoastLevel] = useState<RoastLevel>('light')
  const [showScale, setShowScale] = useState(false)

  const index = STEPS.indexOf(step)
  const go = (next: Step) => setStep(next)
  const grinderSpec = grinder === CUSTOM ? specFor(customUnit) : GRINDER_PRESETS.find((g) => g.name === grinder)?.grinder ?? null
  const hasChoice = step === 'brewer' ? brewers.length > 0 : step === 'filter' ? filters.length > 0
    : step === 'grinder' ? (grinder === CUSTOM ? customName.trim() !== '' : grinder != null) : step === 'beans' ? beanName.trim() !== '' : true

  const finish = () => {
    const byName = new Map(repository.data.get().equipment.map((e) => [e.name, e]))
    const ensure = (preset: EquipmentPreset): Equipment => {
      const existing = byName.get(preset.name)
      if (existing) return existing
      const item = makeEquipment(preset)
      repository.upsertEquipment(item)
      byName.set(item.name, item)
      return item
    }
    const brewer = brewers.map((n) => BREWER_PRESETS.find((p) => p.name === n)).filter((p): p is EquipmentPreset => !!p).map(ensure)[0]
    if (brewer) setup.patch({ brewerId: brewer.id })
    const filter = filters.map((n) => FILTER_PRESETS.find((p) => p.name === n)).filter((p): p is EquipmentPreset => !!p).map(ensure)[0]
    if (filter) setup.patch({ filterId: filter.id })
    let grinderItem: Equipment | undefined
    if (grinder === CUSTOM) {
      const name = sanitized(customName, LIMITS.maxNameLength)
      if (name) {
        grinderItem = byName.get(name) ?? { ...makeEquipment({ name, type: 'grinder', grinder: specFor(customUnit) }) }
        if (!byName.has(name)) repository.upsertEquipment(grinderItem)
      }
    } else {
      const preset = GRINDER_PRESETS.find((p) => p.name === grinder)
      if (preset) grinderItem = ensure(preset)
    }
    if (grinderItem) setup.patch({ grinderId: grinderItem.id })
    const name = sanitized(beanName, LIMITS.maxNameLength)
    if (name) {
      const bean = newBean({ name, roaster: sanitized(roaster, LIMITS.maxNameLength), roastLevel })
      repository.upsertBean(bean)
      setup.patch({ beanId: bean.id })
    }
    // Pin after bean + grinder are set, so the typed setting isn't replaced by a history recommendation.
    if (grinderItem && grindValue != null) setup.pinGrind(grindValue)
    settings.change((s) => ({ ...s, onboardingDone: true }))
    navigate('/brew', true)
  }

  if (step === 'welcome') {
    return (
      <div className="onboarding">
        <div className="welcome">
          <div className="logo"><Coffee size={52} /></div>
          <h1 className="big-title" style={{ fontSize: 30 }}>Welcome to BrewLog</h1>
          <div className="muted">Brew better pour-overs with live guidance from your scale and simple tips after every cup.</div>
          <Feature icon={Droplet} title="Guided pours" text="Soft pings tell you when to stop and when the next pour starts." />
          <Feature icon={ChartLine} title="Every brew logged" text="Pour curve, grind, beans and how it tasted." />
          <Feature icon={Sparkles} title="Tips for your gear" text="“Grind 2 clicks finer” instead of guesswork." />
          <button className="btn-primary" style={{ height: 64, flexDirection: 'column', gap: 0, marginTop: 8 }} onClick={() => go('brewer')}>
            Set up my gear<span className="tiny" style={{ fontWeight: 400 }}>About 1 minute</span>
          </button>
          <button className="link" onClick={() => { settings.change((s) => ({ ...s, onboardingDone: true })); navigate('/brew', true); navigate('/weigh') }}>
            <Scale size={18} />Skip, just use the scale
          </button>
          <div className="small muted">You can run the setup any time from the Gear tab.</div>
        </div>
      </div>
    )
  }

  const toggle = (list: string[], setList: (v: string[]) => void, name: string) =>
    setList(list.includes(name) ? list.filter((n) => n !== name) : [...list, name])

  return (
    <div className="onboarding">
      <div className="row" style={{ padding: '0 8px 8px' }}>
        <button className="icon-btn" aria-label="Back" onClick={() => go(STEPS[index - 1])}><ChevronLeft size={26} /></button>
        <div className="dots">
          {QUESTIONS.map((q) => <span key={q} className={`${STEPS.indexOf(q) <= index ? 'on' : ''} ${q === step ? 'current' : ''}`} />)}
        </div>
        <button className="link" style={{ width: 48, visibility: step === 'done' ? 'hidden' : 'visible' }} onClick={finish}>Skip</button>
      </div>
      <div className="body">
        {step === 'brewer' && (
          <TileStep title="What do you brew with?" subtitle="Pick one or more. The first one becomes your default."
            presets={BREWER_PRESETS} selection={brewers} onToggle={(n) => toggle(brewers, setBrewers, n)}
            describe={(p) => [p.method ? METHOD_NAMES[p.method] : '', Coffee]} />
        )}
        {step === 'filter' && <FilterStep brewers={brewers} filters={filters} onToggle={(n) => toggle(filters, setFilters, n)} />}
        {step === 'grinder' && (
          <>
            <StepHeader title="Which grinder do you use?" subtitle="BrewLog learns your grinder's scale, so tips can say exactly how many clicks to change." />
            {GRINDER_PRESETS.map((p) => (
              <ListRow key={p.name} name={p.name} selected={grinder === p.name}
                detail={p.grinder ? (p.grinder.rangeNote ? `${GRIND_UNIT_NAMES[p.grinder.unit]} · pour-over ${p.grinder.rangeNote}` : GRIND_UNIT_NAMES[p.grinder.unit]) : ''}
                onClick={() => { setGrinder(grinder === p.name ? null : p.name); setGrindValue(null) }} />
            ))}
            <ListRow name="Other grinder" detail="Type its name and how its setting works" selected={grinder === CUSTOM}
              onClick={() => { setGrinder(grinder === CUSTOM ? null : CUSTOM); setGrindValue(null) }} />
            {grinder === CUSTOM && (
              <Card>
                <TextInput label="Grinder name" value={customName} onChange={setCustomName} />
                <div className="chips">{(['clicks', 'numbers', 'dial'] as GrindUnit[]).map((u) => <Chip key={u} title={GRIND_UNIT_NAMES[u]} selected={customUnit === u} onClick={() => setCustomUnit(u)} />)}</div>
                <div className="small muted">You can fine-tune step sizes later in Gear.</div>
              </Card>
            )}
          </>
        )}
        {step === 'beans' && (
          <>
            <StepHeader title="Got a bag of beans open?" subtitle="Optional. Roast level and age help BrewLog explain sour or flat cups. You can also add beans after a brew." />
            <Card>
              <TextInput label="Coffee name, e.g. Ethiopia Guji" value={beanName} onChange={setBeanName} />
              <TextInput label="Roaster (optional)" value={roaster} onChange={setRoaster} />
              <div style={{ fontWeight: 600 }}>Roast level</div>
              <div className="chips">{ROAST_LEVELS.map((r) => <Chip key={r} title={ROAST_NAMES[r]} selected={roastLevel === r} onClick={() => setRoastLevel(r)} />)}</div>
            </Card>
          </>
        )}
        {step === 'scale' && <ScaleStep onOpen={() => setShowScale(true)} />}
        {step === 'done' && (
          <DoneStep brewer={brewers[0]} filter={filters[0]} bean={beanName.trim() || undefined}
            grinder={(grinder === CUSTOM ? customName.trim() || undefined : grinder ?? undefined)
              ?.concat(grindValue != null && grinderSpec ? ` · ${formatGrind(grinderSpec, grindValue)}` : '')} />
        )}
      </div>
      {step === 'grinder' && grinderSpec && (
        <div style={{ padding: '8px 16px 0' }}>
          <Card>
            <div className="small muted" style={{ fontWeight: 600 }}>Your usual pour-over setting (optional)</div>
            <GrindInput spec={grinderSpec} value={grindValue} onValue={setGrindValue} text="" onText={() => undefined} recommendation={null} />
          </Card>
        </div>
      )}
      <div style={{ padding: '10px 16px 0' }}>
        <button className={`btn-primary ${hasChoice ? '' : 'muted-btn'}`} onClick={() => (step === 'done' ? finish() : go(STEPS[index + 1]))}>
          {step === 'done' ? 'Start brewing' : step === 'scale' ? 'Continue' : step === 'beans' ? (hasChoice ? 'Continue' : 'Add beans later') : hasChoice ? 'Continue' : 'Skip this step'}
        </button>
      </div>
      {showScale && <ScaleSheet onClose={() => setShowScale(false)} />}
    </div>
  )
}

function Feature({ icon: Icon, title, text }: { icon: LucideIcon; title: string; text: string }) {
  return (
    <div className="feature" style={{ alignSelf: 'stretch' }}>
      <Icon size={26} className="accent" style={{ flexShrink: 0 }} />
      <div><div style={{ fontWeight: 600 }}>{title}</div><div className="small muted">{text}</div></div>
    </div>
  )
}

function StepHeader({ title, subtitle }: { title: string; subtitle: string }) {
  return (
    <div style={{ marginBottom: 14 }}>
      <h2 className="big-title">{title}</h2>
      <div className="small muted" style={{ marginTop: 4 }}>{subtitle}</div>
    </div>
  )
}

function TileStep({ title, subtitle, presets, selection, onToggle, describe, sectionTitle }: {
  title: string; subtitle: string; presets: EquipmentPreset[]; selection: string[]; onToggle: (name: string) => void
  describe: (p: EquipmentPreset) => [string, LucideIcon]; sectionTitle?: (index: number) => string | null
}) {
  return (
    <>
      <StepHeader title={title} subtitle={subtitle} />
      <div className="tiles">
        {presets.map((preset, i) => {
          const [detail, Icon] = describe(preset)
          const position = selection.indexOf(preset.name)
          const selected = position >= 0
          const section = sectionTitle?.(i)
          return (
            <div key={preset.name} style={{ display: 'contents' }}>
              {section && <div style={{ gridColumn: '1 / -1', marginTop: i ? 8 : 0 }}><SectionHeader title={section} /></div>}
              <button className={`tile ${selected ? 'selected' : ''}`} onClick={() => onToggle(preset.name)} aria-pressed={selected}>
                <span className="row" style={{ width: '100%' }}>
                  <Icon size={24} color={selected ? 'var(--accent)' : 'var(--muted)'} />
                  <span className="grow" />
                  {selected ? <CircleCheck size={22} color="var(--accent)" /> : <Circle size={22} color="var(--muted)" opacity={0.4} />}
                </span>
                <span className="name">{preset.name}</span>
                <span className="small muted">{detail}{position === 0 && selection.length > 1 ? <span className="badge" style={{ marginLeft: 6 }}>Default</span> : null}</span>
              </button>
            </div>
          )
        })}
      </div>
    </>
  )
}

function FilterStep({ brewers, filters, onToggle }: { brewers: string[]; filters: string[]; onToggle: (name: string) => void }) {
  const shapes = new Set(brewers.map((n) => BREWER_PRESETS.find((p) => p.name === n)?.shape).filter(Boolean))
  const matching = shapes.size ? FILTER_PRESETS.filter((p) => !p.shape || shapes.has(p.shape)) : FILTER_PRESETS
  const others = shapes.size ? FILTER_PRESETS.filter((p) => !matching.includes(p)) : []
  return (
    <TileStep title="Which filter papers do you use?" subtitle="Paper flow speed changes drawdown time, so BrewLog uses it in your tips."
      presets={[...matching, ...others]} selection={filters} onToggle={onToggle}
      sectionTitle={(i) => (!shapes.size ? null : i === 0 ? 'Fits your brewer' : i === matching.length && others.length ? 'Other papers' : null)}
      describe={(p) => [
        [p.flow ? `${FLOW_NAMES[p.flow]} flow` : null, p.idealRoast ? `${ROAST_NAMES[p.idealRoast].toLowerCase()} roasts` : null].filter(Boolean).join(' · '),
        p.flow === 'fast' ? Gauge : FileText,
      ]} />
  )
}

function ListRow({ name, detail, selected, onClick }: { name: string; detail: string; selected: boolean; onClick: () => void }) {
  return (
    <button className="list-row" onClick={onClick} aria-pressed={selected}>
      {selected ? <CircleCheck size={22} color="var(--accent)" /> : <Circle size={22} color="var(--muted)" opacity={0.5} />}
      <span><span style={{ fontWeight: 500, display: 'block' }}>{name}</span>{detail && <span className="small muted">{detail}</span>}</span>
    </button>
  )
}

function ScaleStep({ onOpen }: { onOpen: () => void }) {
  const st = useStore(scale.state)
  return (
    <>
      <StepHeader title="Connect your scale" subtitle="BrewLog works with the BOOKOO Themis Mini. Switch it on and tap below. No scale? The timer works on its own." />
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <ScaleCard onClick={onOpen} />
        <Card><Toggle label="Demo scale" detail="Simulated pours to try BrewLog without a scale" checked={st.isDemo} onChange={(v) => scale.setDemo(v)} /></Card>
        <div className="small muted">You can connect any time from the Brew tab. On iPhone, Bluetooth needs the free Bluefy browser.</div>
      </div>
    </>
  )
}

function DoneStep({ brewer, filter, grinder, bean }: { brewer?: string; filter?: string; grinder?: string; bean?: string }) {
  const st = useStore(scale.state)
  const ready = st.isDemo || st.connection === 'connected'
  const rows: [string, LucideIcon, string | undefined][] = [
    ['Brewer', Coffee, brewer], ['Filter', FileText, filter], ['Grinder', SlidersHorizontal, grinder], ['Beans', Leaf, bean],
    ['Scale', Scale, ready ? (st.isDemo ? 'Demo scale' : st.name ?? 'BOOKOO') : 'Timer only for now'],
  ]
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18, paddingTop: 16 }}>
      <div className="logo" style={{ width: 96, height: 96, background: 'var(--good)' }}><Check size={48} /></div>
      <h2 className="big-title" style={{ fontSize: 30 }}>You're all set</h2>
      <div className="muted">Change anything later in the Gear and Beans tabs.</div>
      <Card style={{ alignSelf: 'stretch' }}>
        {rows.map(([title, Icon, value]) => (
          <div key={title} className="row">
            <Icon size={18} className="muted" />
            <span className="grow muted">{title}</span>
            <span style={{ maxWidth: '68%', textAlign: 'right', overflowWrap: 'anywhere', color: value ? undefined : 'var(--muted)' }}>{value ?? 'Skipped'}</span>
          </div>
        ))}
      </Card>
    </div>
  )
}
