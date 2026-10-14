import {
  CircleCheck, CirclePlus, Coffee, Download, FileText, Flame, LayoutGrid, Scale, Search, Settings, SlidersHorizontal, Sparkles, Trash2, Upload,
  Droplet, type LucideIcon,
} from 'lucide-react'
import { useRef, useState } from 'react'
import { cue, goBack, navigate, repository, scale, settings, setup } from '../app'
import { useStore } from '../data/store'
import { fmt1 } from '../domain/format'
import { ALL_PRESETS, makeEquipment } from '../domain/library'
import {
  EQUIPMENT_NAMES, EQUIPMENT_TYPES, FILTER_FLOWS, FLOW_NAMES, GRIND_UNITS, GRIND_UNIT_NAMES, ROAST_LEVELS, ROAST_NAMES,
  type Equipment, type EquipmentType, defaultGrinderSpec, equipmentSubtitle, formatGrindDelta,
} from '../domain/models'
import { BREW_METHODS, METHOD_NAMES } from '../domain/recipe'
import { LIMITS, clamped, sanitized } from '../domain/validation'
import { newId } from '../domain/format'
import { CONNECTION_LABELS } from '../scale/scaleManager'
import { Card, Chip, Field, NumberInput, SectionHeader, Stepper, TextInput, Toggle, TopBar } from '../ui/components'
import { ScaleSheet } from './BrewSetup'

export const EQUIPMENT_ICONS: Record<EquipmentType, LucideIcon> = {
  brewer: Coffee, grinder: SlidersHorizontal, kettle: Flame, filter: FileText, scale: Scale, water: Droplet,
}

export function GearScreen() {
  const data = useStore(repository.data)
  return (
    <div className="screen with-tabs">
      <TopBar title="Gear" />
      <div className="content">
        <Card>
          <button className="row" onClick={() => navigate('/onboarding')}><Sparkles size={20} className="accent" /><span style={{ fontWeight: 500 }}>Setup assistant</span></button>
          <div className="divider" />
          <button className="row" onClick={() => navigate('/settings')}><Settings size={20} className="accent" /><span style={{ fontWeight: 500 }}>Settings & backup</span></button>
        </Card>
        {EQUIPMENT_TYPES.map((type) => {
          const items = data.equipment.filter((e) => e.type === type).sort((a, b) => a.name.localeCompare(b.name))
          if (!items.length) return null
          const Icon = EQUIPMENT_ICONS[type]
          return (
            <div key={type} style={{ display: 'contents' }}>
              <SectionHeader title={EQUIPMENT_NAMES[type]} />
              {items.map((item) => (
                <Card key={item.id} onClick={() => navigate(`/equipment/${item.id}`)}>
                  <div className="row">
                    <Icon size={20} className="accent" />
                    <div className="grow"><div style={{ fontWeight: 500 }}>{item.name}</div>{equipmentSubtitle(item) && <div className="small muted">{equipmentSubtitle(item)}</div>}</div>
                  </div>
                </Card>
              ))}
            </div>
          )
        })}
        <Card>
          <button className="row" onClick={() => navigate('/presets')}><LayoutGrid size={20} className="accent" /><span style={{ fontWeight: 500 }}>Add from presets</span></button>
          <div className="divider" />
          <button className="row" onClick={() => navigate('/equipment/new')}><CirclePlus size={20} className="accent" /><span style={{ fontWeight: 500 }}>Add custom gear</span></button>
        </Card>
        <div className="small muted">Your grinder's scale (clicks, numbers, dial) lets BrewLog suggest exact grind changes. Filter flow speed and roast suitability are used in the analysis.</div>
      </div>
    </div>
  )
}

export function PresetPicker() {
  const data = useStore(repository.data)
  const [search, setSearch] = useState('')
  const order: EquipmentType[] = ['brewer', 'filter', 'grinder', 'kettle', 'scale', 'water']
  return (
    <div className="screen">
      <TopBar title="Add gear" onBack={() => goBack('/gear')} actions={<button className="link" style={{ padding: 8 }} onClick={() => goBack('/gear')}>Done</button>} />
      <div className="content">
        <div className="card search-bar">
          <Search size={18} className="muted" />
          <input className="input" style={{ border: 'none', background: 'transparent' }} aria-label="Search" placeholder="Search" value={search} onChange={(e) => setSearch(e.target.value.slice(0, 60))} />
        </div>
        {order.map((type) => {
          const presets = ALL_PRESETS.filter((p) => p.type === type && p.name.toLowerCase().includes(search.trim().toLowerCase()))
          if (!presets.length) return null
          return (
            <div key={type} style={{ display: 'contents' }}>
              <SectionHeader title={EQUIPMENT_NAMES[type]} />
              {presets.map((preset) => {
                const added = data.equipment.some((e) => e.name === preset.name)
                const detail = preset.notes || (preset.grinder ? `Steps of ${formatGrindDelta(preset.grinder, preset.grinder.adjustStep)}${preset.grinder.rangeNote ? ` · ${preset.grinder.rangeNote}` : ''}` : '')
                return (
                  <Card key={preset.name} onClick={() => { if (!added) repository.upsertEquipment(makeEquipment(preset)) }}>
                    <div className="row">
                      <div className="grow"><div style={{ fontWeight: 500 }}>{preset.name}</div>{detail && <div className="small muted">{detail}</div>}</div>
                      {added ? <CircleCheck size={22} color="var(--good)" aria-label="Added" /> : <CirclePlus size={22} className="accent" aria-label="Add" />}
                    </div>
                  </Card>
                )
              })}
            </div>
          )
        })}
      </div>
    </div>
  )
}

/** Create or edit gear, including grinder scales and filter properties. */
export function EquipmentEditor({ itemId }: { itemId: string }) {
  const data = useStore(repository.data)
  const existing = data.equipment.find((e) => e.id === itemId)
  const [draft, setDraft] = useState<Equipment>(() => existing ?? {
    id: newId(), name: '', type: 'grinder', notes: '', method: 'v60', filterFlow: 'medium', idealRoast: null, grinder: defaultGrinderSpec(), createdAt: Date.now(),
  })
  const set = (patch: Partial<Equipment>) => setDraft((d) => ({ ...d, ...patch }))
  const setGrinder = (patch: Partial<Equipment['grinder']>) => setDraft((d) => ({ ...d, grinder: { ...d.grinder, ...patch } }))
  const name = sanitized(draft.name, LIMITS.maxNameLength)

  const save = () => {
    const step = clamped(draft.grinder.step, 0.01, 100)
    repository.upsertEquipment({
      ...draft,
      name,
      notes: sanitized(draft.notes, LIMITS.maxLongText),
      grinder: { ...draft.grinder, step, adjustStep: Math.max(clamped(draft.grinder.adjustStep, 0.01, 100), step), rangeNote: sanitized(draft.grinder.rangeNote, LIMITS.maxShortText) },
    })
    goBack('/gear')
  }

  return (
    <div className="screen">
      <TopBar title={existing ? 'Edit gear' : 'New gear'} onBack={() => goBack('/gear')} actions={<>
        {existing && <button className="icon-btn" aria-label="Delete" onClick={() => {
          if (window.confirm(`Delete ${existing.name}?`)) { repository.deleteEquipment(existing.id); goBack('/gear') }
        }}><Trash2 size={20} /></button>}
        <button className="link" style={{ padding: 8, opacity: name ? 1 : 0.4 }} disabled={!name} onClick={save}>Save</button>
      </>} />
      <div className="content">
        <Card>
          <TextInput label="Name" value={draft.name} onChange={(v) => set({ name: v })} />
          {!existing && (
            <div className="chips">
              {EQUIPMENT_TYPES.map((t) => <Chip key={t} title={EQUIPMENT_NAMES[t]} icon={EQUIPMENT_ICONS[t]} selected={draft.type === t} onClick={() => set({ type: t })} />)}
            </div>
          )}
        </Card>
        {draft.type === 'brewer' && (
          <>
            <SectionHeader title="Brewer" />
            <Card><div className="chips">{BREW_METHODS.map((m) => <Chip key={m} title={METHOD_NAMES[m]} selected={draft.method === m} onClick={() => set({ method: m })} />)}</div></Card>
          </>
        )}
        {draft.type === 'filter' && (
          <>
            <SectionHeader title="Filter paper" />
            <Card>
              <div className="small muted">Flow speed</div>
              <div className="chips">{FILTER_FLOWS.map((f) => <Chip key={f} title={FLOW_NAMES[f]} selected={draft.filterFlow === f} onClick={() => set({ filterFlow: f })} />)}</div>
              <div className="small muted">Designed for</div>
              <div className="chips">
                <Chip title="Any roast" selected={draft.idealRoast == null} onClick={() => set({ idealRoast: null })} />
                {ROAST_LEVELS.map((r) => <Chip key={r} title={ROAST_NAMES[r]} selected={draft.idealRoast === r} onClick={() => set({ idealRoast: r })} />)}
              </div>
              <div className="small muted">Faster papers shorten drawdown (less extraction). Slower papers lengthen it. Used in the brew analysis.</div>
            </Card>
          </>
        )}
        {draft.type === 'grinder' && (
          <>
            <SectionHeader title="Grind scale" />
            <Card>
              <div className="chips">{GRIND_UNITS.map((u) => <Chip key={u} title={GRIND_UNIT_NAMES[u]} selected={draft.grinder.unit === u} onClick={() => setGrinder({ unit: u })} />)}</div>
              <div className="row">
                <Field label="Smallest step"><NumberInput label="Smallest step" value={draft.grinder.step} onChange={(v) => setGrinder({ step: v ?? 1 })} min={0.01} max={100} decimals={2} /></Field>
                <Field label="Typical adjustment"><NumberInput label="Typical adjustment" value={draft.grinder.adjustStep} onChange={(v) => setGrinder({ adjustStep: v ?? 2 })} min={0.01} max={100} decimals={2} /></Field>
              </div>
              <Toggle label="Lower number = finer" checked={draft.grinder.finerIsLower} onChange={(v) => setGrinder({ finerIsLower: v })} />
              <TextInput label="Pour-over range (e.g. 20–30 clicks)" value={draft.grinder.rangeNote} onChange={(v) => setGrinder({ rangeNote: v })} max={200} />
              <div className="small muted">Example: with a typical adjustment of 2, BrewLog suggests going from 24 to 22 clicks when your brew tastes sour and ran fast.</div>
            </Card>
          </>
        )}
        <SectionHeader title="Notes" />
        <Card><TextInput label="Notes" value={draft.notes} onChange={(v) => set({ notes: v })} max={2000} multiline /></Card>
      </div>
    </div>
  )
}

export function SettingsScreen() {
  const s = useStore(settings)
  const scaleState = useStore(scale.state)
  const [showScale, setShowScale] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const fileInput = useRef<HTMLInputElement>(null)
  const change = (patch: Partial<typeof s>) => settings.change((x) => ({ ...x, ...patch }))

  const exportBackup = async () => {
    const blob = new Blob([await repository.exportBackup()], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = `brewlog-backup-${new Date().toISOString().slice(0, 10)}.json`
    link.click()
    setTimeout(() => URL.revokeObjectURL(url), 1_000)
    setMessage('Backup saved.')
  }

  const importBackup = async (file: File) => {
    if (!window.confirm('Replace all brews, beans, gear and custom recipes on this device with the backup?')) return
    try {
      const result = await repository.importBackup(await file.text())
      setup.adopt(repository.data.get())
      setMessage(`Backup restored: ${result.brews} brews, ${result.beans} beans.`)
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Could not read the backup.')
    }
  }

  return (
    <div className="screen">
      <TopBar title="Settings" onBack={() => goBack('/gear')} />
      <div className="content">
        <SectionHeader title="Scale" />
        <Card>
          <button className="row" onClick={() => setShowScale(true)}>
            <span className="grow" style={{ textAlign: 'left' }}>BOOKOO scale</span>
            <span className="muted">{scaleState.isDemo ? 'Demo' : CONNECTION_LABELS[scaleState.connection]}</span>
          </button>
          <Toggle label="Demo scale (simulated pours)" checked={scaleState.isDemo} onChange={(v) => scale.setDemo(v)} />
        </Card>

        <SectionHeader title="Brew assistant" />
        <Card>
          <div>Auto-start at {fmt1(s.autoStartThreshold)} g</div>
          <input className="range" type="range" min={0.5} max={5} step={0.5} value={s.autoStartThreshold} onChange={(e) => change({ autoStartThreshold: Number(e.target.value) })} />
          <div className="small muted">Ping buffer</div>
          <div className="chips">
            <Chip title="Automatic (flow based)" selected={s.pingLeadMode === 'auto'} onClick={() => change({ pingLeadMode: 'auto' })} />
            <Chip title="Fixed grams" selected={s.pingLeadMode === 'fixed'} onClick={() => change({ pingLeadMode: 'fixed' })} />
          </div>
          {s.pingLeadMode === 'fixed' ? (
            <Stepper label="Ping before target" value={`${Math.round(s.pingLeadGrams)} g`}
              onMinus={() => change({ pingLeadGrams: Math.max(0, s.pingLeadGrams - 1) })} onPlus={() => change({ pingLeadGrams: Math.min(15, s.pingLeadGrams + 1) })} />
          ) : (
            <>
              <div>Reaction time {fmt1(s.reactionTime)} s</div>
              <input className="range" type="range" min={0.2} max={1.5} step={0.1} value={s.reactionTime} onChange={(e) => change({ reactionTime: Number(e.target.value) })} />
            </>
          )}
          <Toggle label="3-2-1 ticks before each step" checked={s.countdownTicks} onChange={(v) => change({ countdownTicks: v })} />
          <Toggle label="Chime at target brew time" checked={s.finishPing} onChange={(v) => change({ finishPing: v })} />
          <Toggle label="Keep screen on while brewing" checked={s.keepAwake} onChange={(v) => change({ keepAwake: v })} />
          <div className="small muted">Automatic buffer = your pour rate × reaction time + 1 g, so you hear the ping early enough to stop right on target. Increase the reaction time if you often overpour.</div>
        </Card>

        <SectionHeader title="Sound & vibration" />
        <Card>
          <Toggle label="Sounds" checked={s.soundEnabled} onChange={(v) => change({ soundEnabled: v })} />
          {s.soundEnabled && (
            <>
              <div>Volume</div>
              <input className="range" type="range" min={0.1} max={1} step={0.05} value={s.soundVolume} onChange={(e) => change({ soundVolume: Number(e.target.value) })} />
              <Toggle label="Play in silent mode (iPhone)" checked={s.silentModeSound} onChange={(v) => change({ silentModeSound: v })} />
            </>
          )}
          <Toggle label="Vibration (Android)" checked={s.hapticsEnabled} onChange={(v) => change({ hapticsEnabled: v })} />
          <div className="row">
            <button className="btn" onClick={() => cue('target')}>Target</button>
            <button className="btn" onClick={() => cue('nextStep')}>Next step</button>
            <button className="btn" onClick={() => cue('finish')}>Finish</button>
          </div>
        </Card>

        <SectionHeader title="Backup" />
        <Card>
          <div className="small muted">Your data lives only in this browser. Save a backup now and then. You can also use it to move your journal to another device.</div>
          <div className="row">
            <button className="btn tinted" onClick={() => void exportBackup()}><Download size={16} />Export backup</button>
            <button className="btn" onClick={() => fileInput.current?.click()}><Upload size={16} />Import</button>
            <input ref={fileInput} type="file" accept="application/json,.json" style={{ display: 'none' }}
              onChange={(e) => { const file = e.target.files?.[0]; if (file) void importBackup(file); e.target.value = '' }} />
          </div>
          {message && <div className="small accent">{message}</div>}
        </Card>

        <SectionHeader title="About" />
        <Card>
          <div className="row"><span className="grow">Version</span><span className="muted">1.0</span></div>
          <div className="small muted">BrewLog has no account, no analytics and no server. Everything stays in this browser on this device.</div>
        </Card>
      </div>
      {showScale && <ScaleSheet onClose={() => setShowScale(false)} />}
    </div>
  )
}
