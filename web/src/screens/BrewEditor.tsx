import { Coffee, FileText, Wrench } from 'lucide-react'
import { useState } from 'react'
import { allRecipes, goBack, repository } from '../app'
import { useStore } from '../data/store'
import { parseNumber } from '../domain/format'
import type { Equipment } from '../domain/models'
import { scaled } from '../domain/recipe'
import { LIMITS, clamped } from '../domain/validation'
import { Card, Field, NumberInput, SectionHeader, SelectRow, TopBar } from '../ui/components'

// Port of BrewEditorView.swift: corrects a saved brew (date, recipe, amounts, time, temperature, gear).
// Edits go to a draft and are only written on Save; the analysis is recalculated from the new values.

const toLocalInput = (millis: number): string => {
  const d = new Date(millis)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export function BrewEditor({ brewId }: { brewId: string }) {
  const data = useStore(repository.data)
  const brew = data.brews.find((b) => b.id === brewId)
  const recipes = allRecipes()
  const [date, setDate] = useState(() => (brew ? toLocalInput(brew.date) : ''))
  const [recipeId, setRecipeId] = useState(brew?.recipe ? brew.recipeId : '')
  const [dose, setDose] = useState<number | null>(brew?.dose ?? null)
  const [finalWeight, setFinalWeight] = useState<number | null>(brew?.finalWeight ?? null)
  const [waterTemp, setWaterTemp] = useState<number | null>(brew?.waterTemp ?? null)
  const [time, setTime] = useState(() => (brew ? `${Math.floor(brew.totalTime / 60)}:${String(Math.round(brew.totalTime % 60)).padStart(2, '0')}` : ''))
  const [brewerId, setBrewerId] = useState(brew?.brewerId ?? null)
  const [grinderId, setGrinderId] = useState(brew?.grinderId ?? null)
  const [filterId, setFilterId] = useState(brew?.filterId ?? null)
  if (!brew) return <div className="screen"><TopBar title="Edit brew" onBack={() => goBack('/journal')} /></div>

  const gear = (type: Equipment['type'], current: string | null, name: string) => {
    const options = data.equipment.filter((e) => e.type === type).map((e) => ({ id: e.id, name: e.name }))
    // A deleted item stays selectable under its old name until something else is picked.
    if (current && !options.some((o) => o.id === current) && name) options.unshift({ id: current, name })
    return options
  }

  const parseTime = (): number => {
    const [m, s] = time.split(':')
    const minutes = parseNumber(m ?? '') ?? 0
    const seconds = s != null ? parseNumber(s) ?? 0 : 0
    return clamped(minutes * 60 + seconds, 0, LIMITS.maxBrewSeconds)
  }

  const save = () => {
    const newDose = clamped(dose ?? brew.dose, 0, LIMITS.maxDose)
    const oldDose = brew.dose
    let next = {
      ...brew,
      date: Math.min(new Date(date).getTime() || brew.date, Date.now()),
      finalWeight: clamped(finalWeight ?? brew.finalWeight, 0, LIMITS.maxWater),
      waterTemp: clamped(waterTemp ?? brew.waterTemp, 0, 100),
      totalTime: parseTime(),
      dose: newDose,
    }
    const chosen = recipes.find((r) => r.id === recipeId)
    if (recipeId !== (brew.recipe ? brew.recipeId : '') && chosen) {
      // Another recipe: store it scaled to this brew's dose, like a brew started from it.
      const recipe = scaled(chosen, newDose > 0 ? newDose : chosen.dose)
      next = { ...next, recipeId: chosen.id, recipeName: chosen.name, recipe, targetWater: recipe.water }
    } else if (newDose !== oldDose && newDose > 0 && brew.recipe) {
      // Same recipe, corrected dose: keep the recipe in step so ratio and pour targets still match.
      const recipe = scaled(brew.recipe, newDose)
      next = { ...next, recipe, targetWater: recipe.water }
    }
    const find = (id: string | null) => data.equipment.find((e) => e.id === id) ?? null
    if (brewerId !== brew.brewerId) {
      const brewer = find(brewerId)
      next = { ...next, brewerId: brewer?.id ?? null, brewerName: brewer?.name ?? '' }
    }
    if (grinderId !== brew.grinderId) {
      const grinder = find(grinderId)
      next = { ...next, grinderId: grinder?.id ?? null, grinderName: grinder?.name ?? '', grinderSpec: grinder?.grinder ?? null }
    }
    if (filterId !== brew.filterId) {
      const filter = find(filterId)
      next = { ...next, filterId: filter?.id ?? null, filterName: filter?.name ?? '', filterFlow: filter?.filterFlow ?? null, filterIdealRoast: filter?.idealRoast ?? null }
    }
    repository.update((d) => ({
      ...d,
      brews: d.brews.map((b) => (b.id === brew.id ? next : b)),
      beans: newDose !== oldDose && brew.beanId
        ? d.beans.map((bean) => (bean.id === brew.beanId ? { ...bean, remaining: clamped(bean.remaining - (newDose - oldDose), 0, LIMITS.maxBagWeight) } : bean))
        : d.beans,
    }))
    goBack(`/brews/${brew.id}`)
  }

  const recipeOptions = [
    ...(!brew.recipe ? [{ id: '', name: brew.recipeName ? `${brew.recipeName} (no recipe)` : 'None' }] : []),
    ...(brew.recipe && !recipes.some((r) => r.id === brew.recipeId) ? [{ id: brew.recipeId, name: brew.recipeName }] : []),
    ...recipes.map((r) => ({ id: r.id, name: r.name })),
  ]

  return (
    <div className="screen">
      <TopBar title="Edit brew" onBack={() => goBack(`/brews/${brew.id}`)} actions={<button className="link" style={{ padding: 8 }} onClick={save}>Save</button>} />
      <div className="content">
        <Card>
          <Field label="Date">
            <input className="input" type="datetime-local" value={date} max={toLocalInput(Date.now())} onChange={(e) => setDate(e.target.value)} />
          </Field>
          <Field label="Recipe">
            <select className="input" value={recipeId} onChange={(e) => setRecipeId(e.target.value)}>
              {recipeOptions.map((o) => <option key={o.id || 'none'} value={o.id}>{o.name}</option>)}
            </select>
          </Field>
          <div className="small muted">Choosing a recipe for a brew without one, for example an imported brew, enables the analysis.</div>
        </Card>
        <SectionHeader title="Amounts" />
        <Card>
          <Field label="Coffee (g)"><NumberInput label="Coffee (g)" value={dose} onChange={setDose} max={LIMITS.maxDose} /></Field>
          <Field label={brew.recipe?.method === 'espresso' ? 'Yield (g)' : 'Water (g)'}>
            <NumberInput label="Water (g)" value={finalWeight} onChange={setFinalWeight} max={LIMITS.maxWater} />
          </Field>
          <Field label="Water temp (°C)"><NumberInput label="Water temp (°C)" value={waterTemp} onChange={setWaterTemp} max={100} /></Field>
          <Field label="Total time (m:ss)">
            <input className="input" inputMode="numeric" value={time} onChange={(e) => setTime(e.target.value.slice(0, 8))} />
          </Field>
        </Card>
        <SectionHeader title="Gear" />
        <Card>
          <SelectRow label="Brewer" icon={Coffee} options={gear('brewer', brewerId, brew.brewerName)} value={brewerId} onChange={setBrewerId} />
          <SelectRow label="Grinder" icon={Wrench} options={gear('grinder', grinderId, brew.grinderName)} value={grinderId} onChange={setGrinderId} />
          <SelectRow label="Filter" icon={FileText} options={gear('filter', filterId, brew.filterName)} value={filterId} onChange={setFilterId} />
        </Card>
      </div>
    </div>
  )
}
