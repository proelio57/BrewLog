import { Leaf, Plus, Trash2 } from 'lucide-react'
import { useState } from 'react'
import { goBack, navigate, repository, setup } from '../app'
import { useStore } from '../data/store'
import { formatDate, grams, mmss } from '../domain/format'
import {
  PROCESS_METHODS, PROCESS_NAMES, ROAST_LEVELS, ROAST_NAMES, type Bean, daysOffRoast, grindDisplay, newBean,
} from '../domain/models'
import { LIMITS, clamped, sanitized } from '../domain/validation'
import { Card, Chip, EmptyState, Field, NumberInput, SectionHeader, Stars, TextInput, Toggle, TopBar } from '../ui/components'

export function BeanList() {
  const data = useStore(repository.data)
  const beans = [...data.beans].sort((a, b) => b.createdAt - a.createdAt)
  const active = beans.filter((b) => !b.isArchived)
  const archived = beans.filter((b) => b.isArchived)
  const row = (bean: Bean) => {
    const days = daysOffRoast(bean)
    return (
      <Card key={bean.id} onClick={() => navigate(`/bean/${bean.id}`)}>
        <div className="row"><span className="title grow">{bean.name}</span><span className="small muted">{ROAST_NAMES[bean.roastLevel]}</span></div>
        {(bean.roaster || bean.origin) && <div className="muted small" style={{ marginTop: -6 }}>{[bean.roaster, bean.origin].filter(Boolean).join(' · ')}</div>}
        <div className="small" style={{ color: days != null && (days < 4 || days > 45) ? 'var(--warn)' : 'var(--muted)' }}>
          {[days != null ? `${days} days` : null, `${grams(bean.remaining)} left`, `${data.brews.filter((b) => b.beanId === bean.id).length} brews`].filter(Boolean).join(' · ')}
        </div>
        {bean.bagWeight > 0 && (
          <div className="progress" style={{ height: 6 }}>
            <div className="fill" style={{ width: `${Math.min(Math.max(bean.remaining / bean.bagWeight, 0), 1) * 100}%`, background: 'var(--good)' }} />
          </div>
        )}
      </Card>
    )
  }
  return (
    <div className="screen with-tabs">
      <TopBar title="Beans" actions={<button className="icon-btn" aria-label="Add beans" onClick={() => navigate('/bean/new')}><Plus size={24} /></button>} />
      {beans.length === 0 ? (
        <EmptyState icon={Leaf} title="No beans yet" message="Add the coffees you're brewing to track freshness, remaining weight and the best grind for each."
          action={<button className="btn tinted" onClick={() => navigate('/bean/new')}>Add beans</button>} />
      ) : (
        <div className="content">
          {active.length > 0 && <SectionHeader title="On the shelf" />}
          {active.map(row)}
          {archived.length > 0 && <SectionHeader title="Finished" />}
          {archived.map(row)}
        </div>
      )}
    </div>
  )
}

/** Create or edit beans. Edits stay local until Save. */
export function BeanEditor({ beanId }: { beanId: string }) {
  const data = useStore(repository.data)
  const existing = data.beans.find((b) => b.id === beanId)
  const [draft, setDraft] = useState<Bean>(() => existing ?? newBean())
  const set = (patch: Partial<Bean>) => setDraft((d) => ({ ...d, ...patch }))
  const name = sanitized(draft.name, LIMITS.maxNameLength)
  const brews = data.brews.filter((b) => b.beanId === beanId).sort((a, b) => b.date - a.date)

  const save = () => {
    const bean: Bean = {
      ...draft,
      name,
      roaster: sanitized(draft.roaster, LIMITS.maxNameLength),
      origin: sanitized(draft.origin, LIMITS.maxNameLength),
      varietal: sanitized(draft.varietal, LIMITS.maxNameLength),
      tastingNotes: sanitized(draft.tastingNotes, LIMITS.maxLongText),
      notes: sanitized(draft.notes, LIMITS.maxLongText),
      roastDate: draft.roastDate != null ? Math.min(draft.roastDate, Date.now()) : null,
      bagWeight: clamped(draft.bagWeight, 0, LIMITS.maxBagWeight),
      remaining: clamped(draft.remaining, 0, LIMITS.maxBagWeight),
    }
    repository.upsertBean(bean)
    if (!existing) setup.patch({ beanId: bean.id })
    goBack('/beans')
  }

  const dateValue = draft.roastDate != null ? new Date(draft.roastDate).toISOString().slice(0, 10) : ''

  return (
    <div className="screen">
      <TopBar title={existing ? 'Edit beans' : 'New beans'} onBack={() => goBack('/beans')} actions={<>
        {existing && <button className="icon-btn" aria-label="Delete" onClick={() => {
          if (window.confirm('Delete these beans? Brews keep their data but lose the link.')) { repository.deleteBean(existing.id); goBack('/beans') }
        }}><Trash2 size={20} /></button>}
        <button className="link" style={{ padding: 8, opacity: name ? 1 : 0.4 }} disabled={!name} onClick={save}>Save</button>
      </>} />
      <div className="content">
        <SectionHeader title="Coffee" />
        <Card>
          <TextInput label="Name (e.g. Ethiopia Guji)" value={draft.name} onChange={(v) => set({ name: v })} />
          <TextInput label="Roaster" value={draft.roaster} onChange={(v) => set({ roaster: v })} />
          <TextInput label="Origin" value={draft.origin} onChange={(v) => set({ origin: v })} />
          <TextInput label="Varietal" value={draft.varietal} onChange={(v) => set({ varietal: v })} />
          <div className="small muted">Process</div>
          <div className="chips">{PROCESS_METHODS.map((p) => <Chip key={p} title={PROCESS_NAMES[p]} selected={draft.process === p} onClick={() => set({ process: p })} />)}</div>
        </Card>
        <SectionHeader title="Roast" />
        <Card>
          <div className="chips">{ROAST_LEVELS.map((r) => <Chip key={r} title={ROAST_NAMES[r]} selected={draft.roastLevel === r} onClick={() => set({ roastLevel: r })} />)}</div>
          <Field label="Roasted on">
            <input className="input" type="date" value={dateValue} max={new Date().toISOString().slice(0, 10)}
              onChange={(e) => set({ roastDate: e.target.value ? Math.min(Date.parse(e.target.value), Date.now()) : null })} />
          </Field>
          <div className="small muted">Roast level and age are used in the analysis. Light roasts need hotter water, very fresh beans extract unevenly, and old beans taste flat.</div>
        </Card>
        <SectionHeader title="Bag" />
        <Card>
          <div className="row">
            <Field label="Bag weight g"><NumberInput label="Bag weight g" value={draft.bagWeight} onChange={(v) => set({ bagWeight: v ?? 0 })} max={10_000} decimals={0} /></Field>
            <Field label="Remaining g"><NumberInput label="Remaining g" value={draft.remaining} onChange={(v) => set({ remaining: v ?? 0 })} max={10_000} decimals={0} /></Field>
          </div>
          <Toggle label="Finished / archived" checked={draft.isArchived} onChange={(v) => set({ isArchived: v })} />
        </Card>
        <SectionHeader title="Notes" />
        <Card>
          <TextInput label="Tasting notes from the roaster" value={draft.tastingNotes} onChange={(v) => set({ tastingNotes: v })} max={2000} multiline />
          <TextInput label="Your notes" value={draft.notes} onChange={(v) => set({ notes: v })} max={2000} multiline />
        </Card>
        {existing && brews.length > 0 && (
          <>
            <SectionHeader title="Grind log" />
            <Card>
              {brews.map((brew) => (
                <div key={brew.id} className="row">
                  <div className="grow"><div style={{ fontWeight: 600 }}>{brew.recipeName}</div><div className="small muted">{formatDate(brew.date)} · {mmss(brew.totalTime)}</div></div>
                  <div style={{ textAlign: 'right' }}><div className="tnum">{grindDisplay(brew) || '–'}</div>{brew.rating > 0 && <Stars rating={brew.rating} />}</div>
                </div>
              ))}
              <div className="small muted">Your brews of this bean, so you can see which grind worked best.</div>
            </Card>
          </>
        )}
      </div>
    </div>
  )
}
