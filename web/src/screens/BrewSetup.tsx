import {
  Bluetooth, ChevronRight, Coffee, FileText, Leaf, Minus, Plus, PlusCircle, Scale, Settings, SlidersHorizontal, Sparkles, Thermometer, Timer, Wrench, X,
} from 'lucide-react'
import { useEffect, useState } from 'react'
import { cue, live, navigate, repository, scale, settings, setup } from '../app'
import { recommendGrind, type GrindRecommendation } from '../analysis/recommender'
import { BrewSession } from '../brewing/brewSession'
import { useStore } from '../data/store'
import { grams, grams1, roundHalfAway } from '../domain/format'
import {
  type Equipment, type GrinderSpec, beanDisplayName, daysOffRoast, equipmentSubtitle, formatGrind, grindSuffix, ROAST_NAMES, GRIND_UNIT_NAMES,
} from '../domain/models'
import { METHOD_NAMES, ratioText } from '../domain/recipe'
import { CONNECTION_LABELS, bluetoothSupported, insecureAddress } from '../scale/scaleManager'
import { Card, IconCircle, NumberInput, SectionHeader, SelectRow, Sheet, Stat, Stepper, TasteBars, Toggle, TopBar } from '../ui/components'

export function BrewSetupScreen() {
  const data = useStore(repository.data)
  const s = useStore(setup.state)
  const appSettings = useStore(settings)
  const scaleState = useStore(scale.state)
  const [showScale, setShowScale] = useState(false)
  const ready = scaleState.isDemo || scaleState.connection === 'connected'

  const beans = data.beans.filter((b) => !b.isArchived).sort((a, b) => b.createdAt - a.createdAt)
  const byType = (type: Equipment['type']) => data.equipment.filter((e) => e.type === type).sort((a, b) => a.name.localeCompare(b.name))
  const brewers = byType('brewer')
  const grinders = byType('grinder')
  const filters = byType('filter')
  const grinder = grinders.find((g) => g.id === s.grinderId) ?? null
  const bean = beans.find((b) => b.id === s.beanId) ?? null
  const filter = filters.find((f) => f.id === s.filterId) ?? null
  const recommendation = recommendGrind(s.beanId, grinder, s.recipe.id, data.brews)
  const recipe = setup.scaledRecipe

  const ids = (items: Equipment[]) => items.map((e) => e.id).join(',')
  useEffect(() => setup.reconcileGear('brewer', brewers.map((e) => e.id)), [ids(brewers)]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => setup.reconcileGear('grinder', grinders.map((e) => e.id)), [ids(grinders)]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => setup.reconcileGear('filter', filters.map((e) => e.id)), [ids(filters)]) // eslint-disable-line react-hooks/exhaustive-deps

  // Apply the history-based grind when bean, grinder or recipe change (unless the grind was set explicitly).
  const recommendationKey = `${s.beanId}|${s.grinderId}|${s.recipe.id}`
  useEffect(() => {
    if (setup.lastRecommendationContext !== recommendationKey || setup.value.grindValue == null) {
      setup.lastRecommendationContext = recommendationKey
      if (!setup.isGrindPinned && recommendation) setup.patch({ grindValue: recommendation.value })
    }
  }, [recommendationKey, recommendation?.value]) // eslint-disable-line react-hooks/exhaustive-deps

  const startBrew = () => {
    const config = {
      recipe, dose: s.dose, waterTemp: s.waterTemp, beanId: bean?.id ?? null,
      brewer: brewers.find((b) => b.id === s.brewerId) ?? null, grinder, filter,
      grindValue: grinder ? s.grindValue : null, grindText: s.grindText,
    }
    live.brew = { config, session: new BrewSession(config.recipe, scale, () => settings.get(), cue) }
    navigate('/live')
  }

  return (
    <div className="screen with-tabs">
      <TopBar title="Brew" actions={<>
        <button className="icon-btn" aria-label="Quick weigh" onClick={() => navigate('/weigh')}><Scale size={22} /></button>
        <button className="icon-btn" aria-label="Settings" onClick={() => navigate('/settings')}><Settings size={22} /></button>
      </>} />
      <div className="content">
        {data.equipment.length === 0 && !appSettings.setupBannerDismissed && (
          <Card>
            <div className="row top">
              <Sparkles className="accent" size={26} />
              <div className="grow">
                <div className="title">Set up your gear</div>
                <div className="small muted">Add your brewer, filter and grinder in about a minute so tips can be precise.</div>
                <button className="btn tinted" style={{ marginTop: 8 }} onClick={() => navigate('/onboarding')}>Start setup</button>
              </div>
              <button className="icon-btn" aria-label="Dismiss" onClick={() => settings.change((x) => ({ ...x, setupBannerDismissed: true }))}><X size={18} /></button>
            </div>
          </Card>
        )}
        <ScaleCard onClick={() => setShowScale(true)} />
        <Card onClick={() => navigate('/recipe-picker')}>
          <div className="row top">
            <div className="grow">
              <div className="headline">{s.recipe.name}</div>
              <div className="muted">{s.recipe.author}</div>
            </div>
            <span className="badge">{METHOD_NAMES[s.recipe.method]}</span>
          </div>
          <div className="muted small">{s.recipe.tasteNotes}</div>
          <TasteBars profile={s.recipe.taste} />
          <span className="link">Change recipe <ChevronRight size={16} /></span>
        </Card>
        <Card>
          <div className="stats">
            <Stat value={grams1(s.dose)} label="Coffee" />
            <Stat value={grams(recipe.water)} label="Water" />
            <Stat value={ratioText(recipe)} label="Ratio" />
            <Stat value={`${Math.round(s.waterTemp)}°`} label="Temp" icon={Thermometer} />
          </div>
          <div className="divider" />
          <Stepper label="Coffee dose" value={grams1(s.dose)} icon={Scale}
            onMinus={() => setup.patch({ dose: Math.max(5, s.dose - 0.5) })} onPlus={() => setup.patch({ dose: Math.min(60, s.dose + 0.5) })} />
          <Stepper label="Water temperature" value={`${Math.round(s.waterTemp)} °C`} icon={Thermometer}
            onMinus={() => setup.patch({ waterTemp: Math.max(70, s.waterTemp - 1) })} onPlus={() => setup.patch({ waterTemp: Math.min(100, s.waterTemp + 1) })} />
          <div className="row small muted"><SlidersHorizontal size={16} /><span>Grind</span><span className="grow" style={{ textAlign: 'right' }}>{s.recipe.grind}</span></div>
        </Card>

        <SectionHeader title="Coffee" />
        <Card>
          <div className="row">
            <div className="grow">
              <SelectRow label="Beans" icon={Leaf} options={beans.map((b) => ({ id: b.id, name: beanDisplayName(b) }))} value={s.beanId}
                onChange={(id) => setup.patch({ beanId: id })} />
            </div>
            <button className="icon-btn accent" aria-label="Add beans" onClick={() => navigate('/bean/new')}><PlusCircle size={24} /></button>
          </div>
          <div className="small muted">
            {bean ? [ROAST_NAMES[bean.roastLevel], daysOffRoast(bean) != null ? `${daysOffRoast(bean)} d off roast` : null, `${grams(bean.remaining)} left`].filter(Boolean).join(' · ')
              : 'Optional. You can also add the beans after brewing.'}
          </div>
        </Card>

        <SectionHeader title="Gear & grind" />
        <Card>
          <GearRow label="Brewer" icon={Coffee} items={brewers} value={s.brewerId} onChange={(id) => setup.patch({ brewerId: id })} />
          <div className="divider" />
          <GearRow label="Filter" icon={FileText} items={filters} value={s.filterId} onChange={(id) => setup.patch({ filterId: id })} />
          {filter && equipmentSubtitle(filter) && <div className="small muted" style={{ textAlign: 'right' }}>{equipmentSubtitle(filter)}</div>}
          <div className="divider" />
          <GearRow label="Grinder" icon={Wrench} items={grinders} value={s.grinderId} onChange={(id) => setup.patch({ grinderId: id })} />
          <GrindInput spec={grinder?.grinder ?? null} value={s.grindValue} onValue={(v) => setup.patch({ grindValue: v })}
            text={s.grindText} onText={(t) => setup.patch({ grindText: t })} recommendation={recommendation} />
        </Card>
      </div>
      <div className="bottom-action">
        <button className="btn-primary" onClick={startBrew}>{ready ? <Scale size={20} /> : <Timer size={20} />}{ready ? 'Start brew' : 'Start brew (timer only)'}</button>
      </div>
      {showScale && <ScaleSheet onClose={() => setShowScale(false)} />}
    </div>
  )
}

function GearRow({ label, icon, items, value, onChange }: { label: string; icon: typeof Coffee; items: Equipment[]; value: string | null; onChange: (id: string | null) => void }) {
  if (!items.length) {
    const Icon = icon
    return (
      <div className="row">
        <span className="muted row"><Icon size={18} />{label}</span>
        <span className="grow" />
        <button className="link" onClick={() => navigate('/presets')}>Add {label.toLowerCase()}</button>
      </div>
    )
  }
  return <SelectRow label={label} icon={icon} options={items.map((e) => ({ id: e.id, name: e.name }))} value={value} onChange={onChange} />
}

/** Grind entry on the grinder's own scale, with finer/coarser buttons and a history-based suggestion. */
export function GrindInput({ spec, value, onValue, text, onText, recommendation }:
  { spec: GrinderSpec | null; value: number | null; onValue: (v: number | null) => void; text: string; onText: (t: string) => void; recommendation: GrindRecommendation | null }) {
  if (!spec) {
    return (
      <>
        <input className="input" aria-label="Grind setting" placeholder="Grind setting (e.g. medium-fine)" value={text} onChange={(e) => onText(e.target.value.slice(0, 80))} />
        <div className="small muted">Add your grinder in Gear to track exact settings and get click-by-click suggestions.</div>
      </>
    )
  }
  const step = (coarser: boolean) => {
    const base = value ?? recommendation?.value ?? 0
    const delta = coarser === spec.finerIsLower ? spec.step : -spec.step
    onValue(Math.max(0, roundHalfAway((base + delta) / spec.step) * spec.step))
  }
  return (
    <>
      <div className="grind">
        <button className="step-btn" onClick={() => step(false)}><span className="circle"><Minus size={22} /></span>Finer</button>
        <div className="center">
          <NumberInput label="Grind setting" value={value} onChange={onValue} max={10_000} decimals={spec.step < 1 ? 2 : 0} className="" placeholder="–" />
          <span className="small muted">{grindSuffix(spec.unit) || GRIND_UNIT_NAMES[spec.unit].toLowerCase()}</span>
        </div>
        <button className="step-btn" onClick={() => step(true)}><span className="circle"><Plus size={22} /></span>Coarser</button>
      </div>
      {recommendation && recommendation.value !== value && (
        <button className="recommend" onClick={() => onValue(recommendation.value)}>
          <Sparkles size={18} className="accent" />
          <span><strong>Use {formatGrind(spec, recommendation.value)}</strong><br /><span className="small muted">{recommendation.reason}</span></span>
        </button>
      )}
      {recommendation && recommendation.value === value && <div className="small muted">✓ {recommendation.reason}</div>}
      {spec.rangeNote && <div className="tiny muted" style={{ textAlign: 'center' }}>Typical pour-over range: {spec.rangeNote}</div>}
    </>
  )
}

export function ScaleCard({ onClick }: { onClick: () => void }) {
  const st = useStore(scale.state)
  const ready = st.isDemo || st.connection === 'connected'
  const color = ready ? 'var(--good)' : st.connection === 'connecting' ? 'var(--warn)' : 'var(--muted)'
  const subtitle = st.isDemo ? 'Simulated pours. Turn off in Settings.'
    : st.connection === 'connected' ? `Connected${st.battery != null ? ` · ${st.battery}% battery` : ''}`
      : st.connection === 'unsupported'
        ? (insecureAddress() ? 'Bluetooth needs an https:// address (or localhost)' : 'Bluetooth not available here (iPhone: use the Bluefy browser)')
        : st.connection === 'idle' ? 'Tap to connect your BOOKOO, or brew with the timer only' : CONNECTION_LABELS[st.connection]
  return (
    <Card onClick={onClick}>
      <div className="row">
        <IconCircle icon={Scale} color={color} size={42} />
        <div className="grow">
          <div className="title">{ready ? (st.isDemo ? 'Demo scale' : st.name ?? 'BOOKOO') : 'No scale connected'}</div>
          <div className="small muted">{subtitle}</div>
        </div>
        {ready ? <span className="title tnum" style={{ fontSize: 20 }}>{grams1(st.weight)}</span> : <span className="link">Connect</span>}
      </div>
    </Card>
  )
}

export function ScaleSheet({ onClose }: { onClose: () => void }) {
  const st = useStore(scale.state)
  return (
    <Sheet onClose={onClose}>
      <div className="title" style={{ fontSize: 20 }}>Scale</div>
      <div className="row"><Bluetooth size={18} className="accent" /><span className="grow">{st.isDemo ? 'Demo scale active' : CONNECTION_LABELS[st.connection]}</span></div>
      {st.connection === 'connected' && !st.isDemo && (
        <>
          <div className="row"><span className="grow muted">Scale</span>{st.name}</div>
          {st.battery != null && <div className="row"><span className="grow muted">Battery</span>{st.battery}%</div>}
          <div className="row"><span className="grow muted">Weight</span><span className="tnum">{grams1(st.weight)}</span></div>
          {st.rejectedPackets > 0 && <div className="row"><span className="grow muted">Ignored invalid packets</span>{st.rejectedPackets}</div>}
          <div className="row">
            <button className="btn" onClick={() => scale.tare()}>Tare</button>
            <button className="btn danger" onClick={() => void scale.disconnect()}>Disconnect</button>
          </div>
        </>
      )}
      {!st.isDemo && st.connection !== 'connected' && (
        bluetoothSupported() ? (
          <>
            <button className="btn-primary" onClick={() => void scale.connect()} disabled={st.connection === 'connecting'}>
              <Bluetooth size={20} />{st.connection === 'connecting' ? 'Connecting…' : 'Search for BOOKOO'}
            </button>
            {st.error && <div className="small" style={{ color: 'var(--danger)' }}>{st.error}</div>}
            <div className="small muted">Switch your BOOKOO Themis Mini on, tap Search and pick it in the browser's list.</div>
          </>
        ) : insecureAddress() ? (
          <div className="notice">
            Bluetooth only works on secure addresses: <strong>https://…</strong> or <strong>http://localhost</strong>. This page was opened over
            plain http (e.g. from another device in your Wi-Fi). Use the https version, or open BrewLog via localhost on the computer that runs it.
            Until then you can brew with the timer or the demo scale.
          </div>
        ) : (
          <div className="notice">
            This browser can't use Bluetooth. On iPhone, open BrewLog in the free <strong>Bluefy</strong> browser from the App Store.
            On Android and computers, use Chrome or Edge. Until then you can brew with the timer or the demo scale.
          </div>
        )
      )}
      <div className="divider" />
      <Toggle label="Demo scale" detail="Simulates pours that follow the recipe, to try BrewLog without a scale." checked={st.isDemo} onChange={(v) => scale.setDemo(v)} />
    </Sheet>
  )
}
