import {
  ArrowLeftRight, Bluetooth, ChevronRight, Circle, CircleCheck, Coffee, Droplet, FileText, Gauge, Leaf, Minus, Plus, PlusCircle, Scale, Settings, SlidersHorizontal, Sparkles, Thermometer, Timer, Wrench, X,
} from 'lucide-react'
import { useEffect, useState } from 'react'
import { cue, espressoSetup, live, machine, navigate, pressure, repository, scale, settings, setup, voice } from '../app'
import { recommendGrind, type GrindRecommendation } from '../analysis/recommender'
import { BrewSession } from '../brewing/brewSession'
import { ShotMonitor } from '../brewing/shotMonitor'
import { useStore } from '../data/store'
import { fmt1, grams, grams1, roundHalfAway } from '../domain/format'
import { GrindConverter } from '../domain/grindConverter'
import {
  type Equipment, type GrinderSpec, beanDisplayName, daysOffRoast, equipmentSubtitle, formatGrind, grindSuffix, ROAST_NAMES, GRIND_UNIT_NAMES, machineReadsPressure,
} from '../domain/models'
import { METHOD_NAMES, ratioText } from '../domain/recipe'
import { CONNECTION_LABELS, bluetoothSupported, insecureAddress } from '../scale/scaleManager'
import { CapsuleSwitch, Card, IconCircle, NumberInput, SectionHeader, SelectRow, Sheet, Stat, Stepper, TasteBars, Toggle, TopBar } from '../ui/components'
import { MachineCard, MachineProfilesSheet } from './Machine'

export function BrewSetupScreen() {
  const data = useStore(repository.data)
  const appSettings = useStore(settings)
  const isEspressoMode = appSettings.brewMode === 'espresso'
  const curSetup = isEspressoMode ? espressoSetup : setup
  const s = useStore(curSetup.state)
  const scaleState = useStore(scale.state)
  const machineState = useStore(machine.state)
  const [showScale, setShowScale] = useState(false)
  const [showProfiles, setShowProfiles] = useState(false)

  const ready = scaleState.isDemo || scaleState.connection === 'connected'

  const beans = data.beans.filter((b) => !b.isArchived).sort((a, b) => b.createdAt - a.createdAt)
  const byType = (type: Equipment['type']) => data.equipment.filter((e) => e.type === type).sort((a, b) => a.name.localeCompare(b.name))

  const brewers = byType('brewer').filter((e) => (e.method === 'espresso') === isEspressoMode)
  const grinders = byType('grinder')
  const filters = byType('filter')
  const waters = byType('water')

  const grinder = grinders.find((g) => g.id === s.grinderId) ?? null
  const bean = beans.find((b) => b.id === s.beanId) ?? null
  const filter = filters.find((f) => f.id === s.filterId) ?? null
  const recommendation = recommendGrind(s.beanId, grinder, s.recipe.id, data.brews)
  const recipe = curSetup.scaledRecipe

  const grinderSpec = grinder?.grinder ? GrindConverter.calibrated(grinder.grinder, grinder.name) : null
  const grindHint = grinderSpec ? GrindConverter.hint(s.recipe.grind, grinderSpec) : null
  const recipeGrindHint = grindHint ? `Recipe ${grindHint} on your grinder` : null

  const ids = (items: Equipment[]) => items.map((e) => e.id).join(',')
  useEffect(() => curSetup.reconcileGear('brewer', brewers.map((e) => e.id)), [ids(brewers)]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => curSetup.reconcileGear('grinder', grinders.map((e) => e.id)), [ids(grinders)]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => curSetup.reconcileGear('filter', filters.map((e) => e.id)), [ids(filters)]) // eslint-disable-line react-hooks/exhaustive-deps

  // Apply history-based grind recommendation
  const recommendationKey = `${s.beanId}|${s.grinderId}|${s.recipe.id}`
  useEffect(() => {
    if (curSetup.lastRecommendationContext !== recommendationKey || curSetup.value.grindValue == null) {
      curSetup.lastRecommendationContext = recommendationKey
      if (!curSetup.isGrindPinned && recommendation) curSetup.patch({ grindValue: recommendation.value })
    }
  }, [recommendationKey, recommendation?.value]) // eslint-disable-line react-hooks/exhaustive-deps

  const startBrew = () => {
    const config = {
      recipe,
      dose: s.dose,
      waterTemp: s.waterTemp,
      beanId: bean?.id ?? null,
      brewer: brewers.find((b) => b.id === s.brewerId) ?? null,
      grinder,
      filter: isEspressoMode ? null : filter,
      grindValue: grinder ? s.grindValue : null,
      grindText: s.grindText,
      water: waters.find((w) => w.id === s.waterId) ?? null,
      profileId: isEspressoMode && machineState.status.profile ? machineState.status.profile : null,
      profileName: isEspressoMode && machineState.status.profile ? machineState.status.profile : null,
    }
    live.brew = {
      config,
      session: new BrewSession(
        config.recipe,
        scale,
        () => settings.get(),
        cue,
        undefined,
        machine,
        pressure,
        (phrase) => voice.speak(phrase),
      ),
    }
    navigate('/live')
  }

  const machineTemp = machineState.connection === 'connected' && machineState.status.targetTemperature != null && machineState.status.targetTemperature >= 70
    ? machineState.status.targetTemperature
    : null
  const targetPressure = ShotMonitor.targetPressure(recipe.pressure, machineState.connection === 'connected' ? machineState.status.targetPressure : null)

  return (
    <div className="screen with-tabs">
      <TopBar title="Brew" actions={<>
        <button className="icon-btn" aria-label="Quick weigh" onClick={() => navigate('/weigh')}><Scale size={22} /></button>
        <button className="icon-btn" aria-label="Settings" onClick={() => navigate('/settings')}><Settings size={22} /></button>
      </>} />
      <div className="content">
        <CapsuleSwitch
          options={[
            { id: 'filter', title: 'Filter' },
            { id: 'espresso', title: 'Espresso' },
          ]}
          selected={appSettings.brewMode}
          onSelect={(id) => {
            settings.change((s) => ({ ...s, brewMode: id as 'filter' | 'espresso' }))
          }}
        />

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

        {isEspressoMode ? (
          <DeviceStrip onOpenScale={() => setShowScale(true)} onOpenSettings={() => navigate('/settings')} />
        ) : (
          <ScaleCard onClick={() => setShowScale(true)} />
        )}

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

        {isEspressoMode ? (
          <Card>
            <div className="stats">
              <Stat value={grams1(s.dose)} label="Dose" />
              <Stat value={grams(recipe.water)} label="Yield" />
              <Stat value={ratioText(recipe)} label="Ratio" />
              <Stat value={`${Math.round(machineTemp ?? s.waterTemp)}°`} label="Temp" icon={Thermometer} />
            </div>
            <div className="divider" />
            <Stepper
              label="Coffee dose"
              value={grams1(s.dose)}
              icon={Scale}
              onMinus={() => curSetup.patch({ dose: Math.max(5, s.dose - 0.5) })}
              onPlus={() => curSetup.patch({ dose: Math.min(30, s.dose + 0.5) })}
            />
            {machineState.connection === 'connected' ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6, margin: '6px 0' }}>
                <div className="row">
                  <span className="muted row" style={{ gap: 6 }}><Thermometer size={16} />Temperature</span>
                  <span className="grow" />
                  <span style={{ fontWeight: 600 }}>{machineTemp != null ? `${Math.round(machineTemp)} °C` : '–'}</span>
                </div>
                <div className="row">
                  <span className="muted row" style={{ gap: 6 }}><Gauge size={16} />Pressure</span>
                  <span className="grow" />
                  <span style={{ fontWeight: 600 }}>{targetPressure != null ? `${fmt1(targetPressure)} bar` : '–'}</span>
                </div>
                <div className="row" onClick={() => setShowProfiles(true)} style={{ cursor: 'pointer' }}>
                  <span className="muted row" style={{ gap: 6 }}><SlidersHorizontal size={16} />Profile</span>
                  <span className="grow" />
                  <span className="row" style={{ fontWeight: 600, gap: 4 }}>
                    {machineState.status.profile ?? '–'}
                    <ChevronRight size={16} className="muted" />
                  </span>
                </div>
                <div className="tiny muted" style={{ textAlign: 'right' }}>from {machine.displayName}</div>
              </div>
            ) : (
              <Stepper
                label="Brew temperature"
                value={`${Math.round(s.waterTemp)} °C`}
                icon={Thermometer}
                onMinus={() => curSetup.patch({ waterTemp: Math.max(70, s.waterTemp - 1) })}
                onPlus={() => curSetup.patch({ waterTemp: Math.min(100, s.waterTemp + 1) })}
              />
            )}
            <div className="row small muted"><SlidersHorizontal size={16} /><span>Grind</span><span className="grow" style={{ textAlign: 'right' }}>{s.recipe.grind}</span></div>
          </Card>
        ) : (
          <Card>
            <div className="stats">
              <Stat value={grams1(s.dose)} label="Coffee" />
              <Stat value={grams(recipe.water)} label="Water" />
              <Stat value={ratioText(recipe)} label="Ratio" />
              <Stat value={`${Math.round(s.waterTemp)}°`} label="Temp" icon={Thermometer} />
            </div>
            <div className="divider" />
            <Stepper label="Coffee dose" value={grams1(s.dose)} icon={Scale}
              onMinus={() => curSetup.patch({ dose: Math.max(5, s.dose - 0.5) })} onPlus={() => curSetup.patch({ dose: Math.min(60, s.dose + 0.5) })} />
            <Stepper label="Water temperature" value={`${Math.round(s.waterTemp)} °C`} icon={Thermometer}
              onMinus={() => curSetup.patch({ waterTemp: Math.max(70, s.waterTemp - 1) })} onPlus={() => curSetup.patch({ waterTemp: Math.min(100, s.waterTemp + 1) })} />
            <div className="row small muted"><SlidersHorizontal size={16} /><span>Grind</span><span className="grow" style={{ textAlign: 'right' }}>{s.recipe.grind}</span></div>
          </Card>
        )}

        {isEspressoMode && <MachineCard recipe={recipe} dose={s.dose} temperature={s.waterTemp} />}

        <SectionHeader title="Coffee" />
        <Card>
          <div className="row">
            <div className="grow">
              <SelectRow label="Beans" icon={Leaf} options={beans.map((b) => ({ id: b.id, name: beanDisplayName(b) }))} value={s.beanId}
                onChange={(id) => curSetup.patch({ beanId: id })} />
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
          <GearRow label={isEspressoMode ? 'Machine' : 'Brewer'} icon={Coffee} items={brewers} value={s.brewerId} onChange={(id) => curSetup.patch({ brewerId: id })} />
          <div className="divider" />
          {!isEspressoMode && <>
            <GearRow label="Filter" icon={FileText} items={filters} value={s.filterId} onChange={(id) => curSetup.patch({ filterId: id })} />
            {filter && equipmentSubtitle(filter) && <div className="small muted" style={{ textAlign: 'right' }}>{equipmentSubtitle(filter)}</div>}
            <div className="divider" />
          </>}
          <GearRow label="Grinder" icon={Wrench} items={grinders} value={s.grinderId} onChange={(id) => curSetup.patch({ grinderId: id })} />
          <GrindInput spec={grinder?.grinder ?? null} value={s.grindValue} onValue={(v) => curSetup.patch({ grindValue: v })}
            text={s.grindText} onText={(t) => curSetup.patch({ grindText: t })} recommendation={recommendation} />
          {recipeGrindHint && (
            <div className="small muted row" style={{ gap: 6, marginTop: 4 }}>
              <ArrowLeftRight size={14} className="accent" />
              <span>{recipeGrindHint}</span>
            </div>
          )}
          {waters.length > 0 && (
            <>
              <div className="divider" />
              <GearRow label="Water" icon={Droplet} items={waters} value={s.waterId} onChange={(id) => curSetup.patch({ waterId: id })} />
            </>
          )}
        </Card>

        <SectionHeader title="Before you brew" />
        <Card>
          <StepCheck label="Weigh the beans" detail={ready ? 'On the scale, before the brewer goes on' : 'With a scale connected'}
            checked={appSettings.weighBeansFirst} onChange={(v) => settings.change((x) => ({ ...x, weighBeansFirst: v }))} />
          {!isEspressoMode && (
            <StepCheck label="Rinse the paper" detail="With hot water, then discard it"
              checked={appSettings.rinsePaper} onChange={(v) => settings.change((x) => ({ ...x, rinsePaper: v }))} />
          )}
        </Card>
      </div>
      <div className="bottom-action">
        <button className="btn-primary" onClick={startBrew}>
          {isEspressoMode ? <Coffee size={20} /> : ready ? <Scale size={20} /> : <Timer size={20} />}
          {isEspressoMode ? 'Pull shot' : ready ? 'Start brew' : 'Start brew (timer only)'}
        </button>
      </div>
      {showScale && <ScaleSheet onClose={() => setShowScale(false)} />}
      {showProfiles && <MachineProfilesSheet onClose={() => setShowProfiles(false)} />}
    </div>
  )
}

function DeviceStrip({ onOpenScale, onOpenSettings }: { onOpenScale: () => void; onOpenSettings: () => void }) {
  const scaleState = useStore(scale.state)
  const machineState = useStore(machine.state)
  const sensorState = useStore(pressure.state)
  const scaleReady = scaleState.isDemo || scaleState.connection === 'connected'
  const machineConnected = machineState.connection === 'connected'
  const readsPressure = machineReadsPressure(machineState.kind, machineState.status)

  const machineVal = machineConnected
    ? (machineState.status.temperature != null ? `${Math.round(machineState.status.temperature)} °C` : 'Connected')
    : machineState.kind === 'none' ? 'Set up' : machineState.connection === 'connecting' ? 'Connecting' : 'Offline'

  const pressureVal = readsPressure
    ? (machineConnected && machineState.status.pressure != null ? `${fmt1(machineState.status.pressure)} bar` : '–')
    : pressure.isReady ? `${fmt1(sensorState.pressure)} bar` : (sensorState.enabled ? CONNECTION_LABELS[sensorState.connection] : 'Off')

  return (
    <div className="device-strip">
      <button className="device-tile" onClick={onOpenScale}>
        <div className="row" style={{ gap: 4 }}>
          <Scale size={14} className={scaleReady ? 'accent' : 'muted'} />
          <span style={{ width: 6, height: 6, borderRadius: 3, background: scaleReady ? 'var(--good)' : 'var(--muted)' }} />
        </div>
        <div className="tiny muted">Scale</div>
        <div style={{ fontWeight: 600, fontSize: 13 }}>{scaleReady ? grams1(scaleState.weight) : 'Connect'}</div>
      </button>

      <button className="device-tile" onClick={onOpenSettings}>
        <div className="row" style={{ gap: 4 }}>
          <Coffee size={14} className={machineConnected ? 'accent' : 'muted'} />
          <span style={{ width: 6, height: 6, borderRadius: 3, background: machineConnected ? 'var(--good)' : 'var(--muted)' }} />
        </div>
        <div className="tiny muted">{machineState.kind === 'none' ? 'Machine' : machine.displayName}</div>
        <div style={{ fontWeight: 600, fontSize: 13 }}>{machineVal}</div>
      </button>

      <button className="device-tile" onClick={onOpenSettings}>
        <div className="row" style={{ gap: 4 }}>
          <Gauge size={14} className={readsPressure && machineConnected ? 'accent' : pressure.isReady ? 'accent' : 'muted'} />
          <span style={{ width: 6, height: 6, borderRadius: 3, background: (readsPressure ? machineConnected : pressure.isReady) ? 'var(--good)' : 'var(--muted)' }} />
        </div>
        <div className="tiny muted">Pressure</div>
        <div style={{ fontWeight: 600, fontSize: 13 }}>{pressureVal}</div>
      </button>
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

function StepCheck({ label, detail, checked, onChange }: { label: string; detail: string; checked: boolean; onChange: (checked: boolean) => void }) {
  return (
    <button className="row" role="checkbox" aria-checked={checked} onClick={() => onChange(!checked)}
      style={{ width: '100%', background: 'none', border: 'none', padding: '6px 0', textAlign: 'left', color: 'inherit', cursor: 'pointer' }}>
      {checked ? <CircleCheck size={22} className="accent" /> : <Circle size={22} color="var(--muted)" />}
      <span>
        <div style={{ fontWeight: 600 }}>{label}</div>
        <div className="small muted">{detail}</div>
      </span>
    </button>
  )
}
