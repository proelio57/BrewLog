import {
  CheckCircle2, Coffee, Droplet, FileText, Leaf, Pencil, PlusCircle, RotateCcw, Sparkles, Thermometer, Timer, SlidersHorizontal, TriangleAlert, Wrench,
} from 'lucide-react'
import { useEffect, useState } from 'react'
import { allRecipes, goBack, navigate, presetRecipes, repository, setup } from '../app'
import { weightDelta, type BrewAnalysis } from '../analysis/analyzer'
import { analyzeBrew } from '../analysis/recommender'
import { useStore } from '../data/store'
import { Extraction } from '../domain/extraction'
import { fmt1, formatDate, grams, grams1, mmss, roundHalfAway } from '../domain/format'
import { FEEDBACK_INFO, TASTE_FEEDBACK, type Brew, type MachineSample, type TasteFeedback, type WeightSample, beanDisplayName, brewRatio, formatGrind, grindDisplay } from '../domain/models'
import { METHOD_NAMES } from '../domain/recipe'
import { sanitized } from '../domain/validation'
import { BrewChart, MachineChart } from '../ui/chart'
import {
  Card, Chip, FEEDBACK_ICONS, FINDING_STYLE, NumberInput, SectionHeader, SelectRow, StarRating, Stat, TopBar,
} from '../ui/components'
import { ExtractionChart } from './Tools'

/** Post-brew review (rating, taste, analysis, suggestions). Also the journal detail screen. */
export function BrewDetail({ brewId, isNew }: { brewId: string; isNew: boolean }) {
  const data = useStore(repository.data)
  const brew = data.brews.find((b) => b.id === brewId)
  const [samples, setSamples] = useState<WeightSample[]>(() => repository.peekSamples(brewId) ?? [])
  const [machineSamples, setMachineSamples] = useState<MachineSample[]>([])

  useEffect(() => {
    void repository.samples(brewId).then(setSamples)
    void repository.machineSamples(brewId).then(setMachineSamples)
  }, [brewId])
  useEffect(() => {
    if (!brew) navigate('/journal', true)
  }, [brew])

  const bean = brew ? data.beans.find((b) => b.id === brew.beanId) ?? null : null
  const analysis = brew ? analyzeBrew(brew, data.brews, bean, samples, machineSamples, presetRecipes()) : null
  const espresso = brew?.recipe?.method === 'espresso'

  // Remember the grind the analysis suggests, so the next brew of this bean starts there.
  useEffect(() => {
    if (brew && analysis && brew.suggestedGrind !== analysis.suggestedGrind) {
      repository.updateBrew(brew.id, (b) => ({ ...b, suggestedGrind: analysis.suggestedGrind }))
    }
  }, [brew, analysis?.suggestedGrind]) // eslint-disable-line react-hooks/exhaustive-deps

  if (!brew) return null

  return (
    <div className="screen">
      <TopBar title={isNew ? 'How was it?' : brew.recipeName} onBack={isNew ? undefined : () => goBack('/journal')}
        actions={isNew ? <button className="link" style={{ padding: 8 }} onClick={() => navigate('/journal', true)}>Save</button>
          : <button className="icon-btn" aria-label="Edit" onClick={() => navigate(`/brew-edit/${brew.id}`)}><Pencil size={20} /></button>} />
      <div className="content">
        <Card>
          <div className="row top">
            <div className="grow">
              <div className="title" style={{ fontSize: 20 }}>{brew.recipeName}</div>
              <div className="small muted">{formatDate(brew.date, true)}</div>
            </div>
            {brew.recipe && <span className="badge">{METHOD_NAMES[brew.recipe.method]}</span>}
          </div>
          <div className="stats">
            <Stat value={mmss(brew.totalTime)} label="Time" icon={Timer} />
            <Stat value={grams(brew.finalWeight)} label={espresso ? 'Yield' : 'Water'} icon={Droplet} />
            <Stat value={`1:${fmt1(brewRatio(brew))}`} label="Ratio" />
            <Stat value={grindDisplay(brew) || '–'} label="Grind" icon={SlidersHorizontal} />
          </div>
        </Card>

        {brew.usedScale && brew.recipe && samples.length > 0 && (
          <>
            <SectionHeader title="Pour curve" />
            <Card><BrewChart samples={samples} recipe={brew.recipe} height={230} showFlowRange /></Card>
          </>
        )}
        {machineSamples.length > 0 && (
          <>
            <SectionHeader title="Pressure & flow" />
            <Card><MachineChart samples={machineSamples} targetPressure={brew.recipe?.pressure} height={160} /></Card>
          </>
        )}

        <SectionHeader title="Taste" />
        <Card>
          <StarRating rating={brew.rating} onChange={(rating) => repository.updateBrew(brew.id, (b) => ({ ...b, rating }))} />
          <div className="chips">
            {TASTE_FEEDBACK.map((item) => (
              <Chip key={item} title={FEEDBACK_INFO[item].title} icon={FEEDBACK_ICONS[item]} selected={brew.feedback.includes(item)} green={item === 'perfect'}
                onClick={() => repository.updateBrew(brew.id, (b) => toggleFeedback(b, item))} />
            ))}
          </div>
          {brew.feedback.length === 1 && <div className="small muted">{FEEDBACK_INFO[brew.feedback[0]].subtitle}</div>}
        </Card>

        {analysis && <Suggestions brew={brew} analysis={analysis} />}
        {analysis && <Findings analysis={analysis} />}
        {analysis && analysis.pours.length > 0 && <Pours analysis={analysis} />}
        <BrewExtractionCard brew={brew} espresso={espresso} />
        <Details brew={brew} />

        {!isNew && (
          <button className="btn tinted" style={{ justifyContent: 'center', padding: 14 }} onClick={() => brewAgain(brew)}>
            <RotateCcw size={18} />
            {brew.suggestedGrind != null && brew.suggestedGrind !== brew.grindValue ? 'Brew again with suggestions' : 'Brew again'}
          </button>
        )}
      </div>
    </div>
  )
}

function BrewExtractionCard({ brew, espresso }: { brew: Brew; espresso: boolean }) {
  const effectiveBeverage = brew.drinkWeight ?? Extraction.estimatedBeverage(brew.finalWeight, brew.dose, espresso)
  const reading = brew.tds != null && brew.tds > 0
    ? Extraction.evaluate(brew.tds, effectiveBeverage, brew.dose, espresso)
    : null

  return (
    <>
      <SectionHeader title="Extraction" />
      <Card>
        <div className="row">
          <span className="grow muted">TDS (%)</span>
          <NumberInput
            label="TDS"
            value={brew.tds ?? null}
            onChange={(v) => repository.updateBrew(brew.id, (b) => ({ ...b, tds: v }))}
            max={30}
            decimals={2}
            placeholder={espresso ? 'e.g. 9.5' : 'e.g. 1.35'}
            style={{ width: 100, textAlign: 'right' }}
          />
        </div>
        <div className="row">
          <span className="grow muted">{espresso ? 'Shot weight (g)' : 'Drink weight (g)'}</span>
          <NumberInput
            label="Drink weight"
            value={brew.drinkWeight ?? null}
            onChange={(v) => repository.updateBrew(brew.id, (b) => ({ ...b, drinkWeight: v }))}
            max={2000}
            decimals={1}
            placeholder={`≈ ${Math.round(effectiveBeverage)}`}
            style={{ width: 100, textAlign: 'right' }}
          />
        </div>
        {reading ? (
          <>
            <div className="divider" />
            <div className="row">
              <span className="grow muted">Extraction yield</span>
              <span style={{ fontWeight: 600, fontSize: 16 }}>{fmt1(reading.yield)} %</span>
            </div>
            <div className="row">
              <span className="grow muted">Strength</span>
              <span style={{ fontWeight: 600 }}>{fmt1(reading.tds)} % TDS · {reading.strength}</span>
            </div>
            <div className="row" style={{ color: reading.verdict === 'ideal' ? 'var(--good)' : 'var(--warn)' }}>
              {reading.verdict === 'ideal' ? <CheckCircle2 size={18} /> : <TriangleAlert size={18} />}
              <span style={{ fontWeight: 600 }}>{reading.verdict === 'ideal' ? 'Ideal extraction' : reading.verdict === 'under' ? 'Under-extracted' : 'Over-extracted'}</span>
            </div>
            <div className="small muted">{reading.advice}</div>
            <div className="divider" />
            <ExtractionChart readings={[reading]} espresso={espresso} height={180} />
          </>
        ) : (
          <div className="small muted">
            Have a refractometer? Enter the TDS to see the extraction yield and whether your brew was under- or over-extracted.
          </div>
        )}
      </Card>
    </>
  )
}

function toggleFeedback(brew: Brew, item: TasteFeedback): Brew {
  let set = new Set(brew.feedback)
  let rating = brew.rating
  if (set.has(item)) set.delete(item)
  else if (item === 'perfect') {
    set = new Set(['perfect'])
    if (rating < 4) rating = 5
  } else {
    set.delete('perfect')
    set.add(item)
    if (item === 'weak') set.delete('strong')
    if (item === 'strong') set.delete('weak')
  }
  return { ...brew, feedback: [...set], rating }
}

function brewAgain(brew: Brew): void {
  const equipment = repository.data.get().equipment
  const exists = (id: string | null) => id != null && equipment.some((e) => e.id === id)
  if (brew.recipe) {
    setup.select(allRecipes().find((r) => r.id === brew.recipeId) ?? brew.recipe)
    setup.patch({ dose: brew.dose, waterTemp: brew.waterTemp })
  }
  setup.patch({ beanId: brew.beanId, grindText: brew.grindSetting })
  if (exists(brew.brewerId)) setup.patch({ brewerId: brew.brewerId })
  if (exists(brew.filterId)) setup.patch({ filterId: brew.filterId })
  if (exists(brew.grinderId)) setup.patch({ grinderId: brew.grinderId })
  setup.pinGrind(brew.suggestedGrind ?? brew.grindValue)
  navigate('/brew', true)
}

function Suggestions({ brew, analysis }: { brew: Brew; analysis: BrewAnalysis }) {
  const [showAll, setShowAll] = useState(false)
  const visible = showAll ? analysis.suggestions : analysis.suggestions.slice(0, 3)
  if (!analysis.suggestions.length) return null
  const next = analysis.suggestedGrind
  return (
    <>
      <SectionHeader title="Suggestions for next time" />
      <Card>
        {visible.map((s, i) => (
          <div key={i} className="row top">
            <Sparkles size={20} className="accent" style={{ flexShrink: 0, marginTop: 2 }} />
            <div className="grow">
              <div style={{ fontWeight: 600 }}>{s.title}</div>
              <div className="small muted">{s.detail}</div>
              {s.evidence.length > 0 && <div className="tiny muted">{s.evidence.join(' · ')}</div>}
            </div>
          </div>
        ))}
        {analysis.suggestions.length > 3 && (
          <button className="link" onClick={() => setShowAll(!showAll)}>{showAll ? 'Show less' : `Show ${analysis.suggestions.length - 3} more`}</button>
        )}
        {next != null && brew.grinderSpec && brew.feedback.length > 0 && (
          <div className="row small accent" style={{ gap: 6 }}>
            <Sparkles size={16} />Next time BrewLog will pre-fill {formatGrind(brew.grinderSpec, next)} for {brew.beanId ? 'this bean' : 'this recipe'}.
          </div>
        )}
      </Card>
    </>
  )
}

function Findings({ analysis }: { analysis: BrewAnalysis }) {
  const [showAll, setShowAll] = useState(false)
  const visible = showAll ? analysis.findings : analysis.findings.slice(0, 5)
  return (
    <>
      <SectionHeader title="Brew data" />
      <Card>
        {visible.map((f, i) => {
          const { icon: Icon, color } = FINDING_STYLE[f.level]
          return (
            <div key={i} className="row top">
              <Icon size={20} color={color} style={{ flexShrink: 0 }} />
              <div><div style={{ fontWeight: 600, fontSize: 15 }}>{f.title}</div><div className="small muted">{f.detail}</div></div>
            </div>
          )
        })}
        {analysis.findings.length > 5 && (
          <button className="link" onClick={() => setShowAll(!showAll)}>{showAll ? 'Show less' : `Show all ${analysis.findings.length}`}</button>
        )}
      </Card>
    </>
  )
}

function Pours({ analysis }: { analysis: BrewAnalysis }) {
  return (
    <>
      <SectionHeader title="Pours" />
      <Card>
        <div className="grid4">
          <span className="head">#</span><span className="head">Plan</span><span className="head">Actual</span><span className="head">Flow</span>
          {analysis.pours.map((p) => {
            const off = Math.abs(weightDelta(p) ?? 0) > Math.max(3, p.target * 0.04)
            return [
              <strong key={`n${p.stepIndex}`}>{p.step.kind === 'bloom' ? 'B' : p.number}</strong>,
              <span key={`p${p.stepIndex}`} className="tnum">{mmss(p.step.time)} → {Math.trunc(p.target)} g</span>,
              p.actualStart != null
                ? <span key={`a${p.stepIndex}`} className="tnum" style={{ color: off ? 'var(--warn)' : undefined }}>{mmss(p.actualStart)} → {roundHalfAway(p.reached ?? 0)} g</span>
                : <span key={`a${p.stepIndex}`} className="muted">not detected</span>,
              <span key={`f${p.stepIndex}`} className="tnum">{p.averageFlow != null ? fmt1(p.averageFlow) : '–'}</span>,
            ]
          })}
        </div>
      </Card>
    </>
  )
}

function Details({ brew }: { brew: Brew }) {
  const data = useStore(repository.data)
  const [notes, setNotes] = useState(brew.notes)
  const beans = data.beans.filter((b) => !b.isArchived || b.id === brew.beanId)
  return (
    <>
      <SectionHeader title="Details" />
      <Card>
        <div className="row">
          <div className="grow">
            <SelectRow label="Beans" icon={Leaf} options={beans.map((b) => ({ id: b.id, name: beanDisplayName(b) }))} value={brew.beanId}
              onChange={(id) => repository.assignBean(brew.id, id)} />
          </div>
          <button className="icon-btn accent" aria-label="Add beans" onClick={() => navigate('/bean/new')}><PlusCircle size={22} /></button>
        </div>
        <div className="divider" />
        {brew.grinderSpec ? (
          <div className="row">
            <Wrench size={18} className="muted" />
            <span className="grow muted">{brew.grinderName}</span>
            <NumberInput label="Grind" value={brew.grindValue} onChange={(v) => repository.updateBrew(brew.id, (b) => ({ ...b, grindValue: v }))}
              max={10_000} decimals={brew.grinderSpec.step < 1 ? 2 : 0} style={{ width: 100, textAlign: 'right' }} />
          </div>
        ) : (
          <input className="input" aria-label="Grind" placeholder="Grind" value={brew.grindSetting}
            onChange={(e) => repository.updateBrew(brew.id, (b) => ({ ...b, grindSetting: e.target.value.slice(0, 80) }))} />
        )}
        <div className="divider" />
        <DetailRow icon={Coffee} label="Brewer" value={brew.brewerName} />
        {(brew.recipe?.method !== 'espresso' || brew.filterName) && <DetailRow icon={FileText} label="Filter" value={brew.filterName} />}
        {brew.waterName && <DetailRow icon={Droplet} label="Water" value={brew.waterName} />}
        {brew.profileName && <DetailRow icon={SlidersHorizontal} label="Profile" value={brew.profileName} />}
        <DetailRow icon={Droplet} label="Dose" value={grams1(brew.dose)} />
        <DetailRow icon={Thermometer} label="Water temp" value={`${Math.round(brew.waterTemp)} °C`} />
        <textarea className="input" aria-label="Notes" placeholder="Notes: aroma, flavours, what you changed…" value={notes}
          onChange={(e) => {
            setNotes(e.target.value.slice(0, 2_000))
            repository.updateBrew(brew.id, (b) => ({ ...b, notes: sanitized(e.target.value, 2_000) }))
          }} />
      </Card>
    </>
  )
}

function DetailRow({ icon: Icon, label, value }: { icon: typeof Coffee; label: string; value: string }) {
  return (
    <div className="row">
      <Icon size={18} className="muted" />
      <span className="grow muted">{label}</span>
      <span>{value || '–'}</span>
    </div>
  )
}
