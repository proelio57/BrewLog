import { CircleCheck, Copy, Droplet, Lightbulb, Pencil, Plus, Share2, SlidersHorizontal, Trash2 } from 'lucide-react'
import { useState } from 'react'
import { allRecipes, goBack, navigate, recipeFeed, repository, setup } from '../app'
import { useStore } from '../data/store'
import { grams, mmss, newId } from '../domain/format'
import { blankRecipe } from '../domain/library'
import { encodeRecipes, recipeFileName } from '../import/recipeFile'
import { ImportButton, shareOrDownload } from '../ui/files'
import {
  BREW_METHODS, METHOD_NAMES, STEP_KINDS, STEP_TITLES, isPour, ratioText, stepHeadline, type BrewMethod, type Recipe, type RecipeStep,
} from '../domain/recipe'
import { validatedRecipe } from '../domain/validation'
import { Card, Chip, Field, NumberInput, STEP_ICONS, SectionHeader, Stat, Stepper, TasteBars, TextInput, TopBar } from '../ui/components'

function RecipeSections({ custom, onPick, selectedId }: { custom: Recipe[]; onPick: (r: Recipe) => void; selectedId?: string }) {
  const presets = useStore(recipeFeed.presets)
  return (
    <>
      {custom.length > 0 && <SectionHeader title="My recipes" />}
      {custom.map((r) => <RecipeRow key={'c' + r.id} recipe={r} onClick={() => onPick(r)} selected={r.id === selectedId} />)}
      {BREW_METHODS.map((method) => {
        const recipes = presets.filter((r) => r.method === method)
        if (!recipes.length) return null
        return (
          <div key={method} style={{ display: 'contents' }}>
            <SectionHeader title={METHOD_NAMES[method]} />
            {recipes.map((r) => <RecipeRow key={r.id} recipe={r} onClick={() => onPick(r)} selected={r.id === selectedId} />)}
          </div>
        )
      })}
    </>
  )
}

function RecipeRow({ recipe, onClick, selected }: { recipe: Recipe; onClick: () => void; selected?: boolean }) {
  return (
    <Card onClick={onClick}>
      <div className="row">
        <span className="title grow">{recipe.name}</span>
        <span className="small muted">{ratioText(recipe)}</span>
        {selected && <CircleCheck size={20} className="accent" />}
      </div>
      <div className="small muted" style={{ marginTop: -6 }}>{recipe.author}</div>
      <div className="small muted">{recipe.tasteNotes}</div>
      <div className="tiny muted">{grams(recipe.dose)} · {grams(recipe.water)} · {Math.round(recipe.temperature)}° · {mmss(recipe.targetTime)}</div>
    </Card>
  )
}

export function RecipeList() {
  const data = useStore(repository.data)
  return (
    <div className="screen with-tabs">
      <TopBar title="Recipes" actions={<>
        <ImportButton className="icon-btn" label="Import recipes or a backup" />
        {data.customRecipes.length > 0 && (
          <button className="icon-btn" aria-label="Share my recipes"
            onClick={() => void shareOrDownload(recipeFileName(data.customRecipes), encodeRecipes(data.customRecipes))}><Share2 size={20} /></button>
        )}
        <button className="icon-btn" aria-label="New recipe" onClick={() => navigate('/recipe-edit/new')}><Plus size={24} /></button>
      </>} />
      <div className="content"><RecipeSections custom={data.customRecipes} onPick={(r) => navigate(`/recipe/${encodeURIComponent(r.id)}`)} /></div>
    </div>
  )
}

export function RecipePicker() {
  const data = useStore(repository.data)
  const s = useStore(setup.state)
  return (
    <div className="screen">
      <TopBar title="Choose recipe" onBack={() => goBack()} />
      <div className="content">
        <RecipeSections custom={data.customRecipes} selectedId={s.recipe.id} onPick={(r) => { setup.select(r); goBack() }} />
      </div>
    </div>
  )
}

export function RecipeDetail({ recipeId }: { recipeId: string }) {
  useStore(repository.data)
  const recipe = allRecipes().find((r) => r.id === decodeURIComponent(recipeId))
  if (!recipe) return <div className="screen"><TopBar title="Recipe" onBack={() => goBack('/recipes')} /></div>
  const isCustom = recipe.isCustom === true
  const id = encodeURIComponent(recipe.id)
  return (
    <div className="screen">
      <TopBar title={recipe.name} onBack={() => goBack('/recipes')} actions={<>
        {isCustom && <button className="icon-btn" aria-label="Edit" onClick={() => navigate(`/recipe-edit/${id}`)}><Pencil size={20} /></button>}
        <button className="icon-btn" aria-label="Duplicate and edit" onClick={() => navigate(`/recipe-edit/${id}?dup=1`)}><Copy size={20} /></button>
        <button className="icon-btn" aria-label="Share as file" onClick={() => void shareOrDownload(recipeFileName([recipe]), encodeRecipes([recipe]))}><Share2 size={20} /></button>
        {isCustom && <button className="icon-btn" aria-label="Delete" onClick={() => {
          if (window.confirm('Delete this recipe?')) { repository.deleteRecipe(recipe.id); goBack('/recipes') }
        }}><Trash2 size={20} /></button>}
      </>} />
      <div className="content">
        <Card>
          <div className="row"><span className="badge">{METHOD_NAMES[recipe.method]}</span><span className="grow" /><span className="small muted">{recipe.author}</span></div>
          {recipe.summary && <div>{recipe.summary}</div>}
        </Card>
        <SectionHeader title="How it should taste" />
        <Card>{recipe.tasteNotes && <div>{recipe.tasteNotes}</div>}<TasteBars profile={recipe.taste} /></Card>
        <SectionHeader title="Parameters" />
        <Card>
          <div className="stats"><Stat value={grams(recipe.dose)} label="Coffee" /><Stat value={grams(recipe.water)} label="Water" /><Stat value={ratioText(recipe)} label="Ratio" /></div>
          <div className="stats"><Stat value={`${Math.round(recipe.temperature)} °C`} label="Temp" /><Stat value={mmss(recipe.targetTime)} label="Total time" />
            <Stat value={`${Math.trunc(recipe.flowMin)}–${Math.trunc(recipe.flowMax)}`} label="Pour g/s" /></div>
          <div className="divider" />
          <div className="row small"><SlidersHorizontal size={16} />{recipe.grind}</div>
        </Card>
        <SectionHeader title="Steps" />
        <Card>
          {recipe.steps.map((step, i) => {
            const Icon = STEP_ICONS[step.kind]
            return (
              <div key={i} className="row top">
                <strong className="tnum" style={{ width: 48 }}>{mmss(step.time)}</strong>
                <Icon size={20} className="accent" />
                <div><div style={{ fontWeight: 600 }}>{stepHeadline(step)}</div>{step.note && <div className="small muted">{step.note}</div>}</div>
              </div>
            )
          })}
        </Card>
        {recipe.tips.length > 0 && (
          <>
            <SectionHeader title="Tips" />
            <Card>{recipe.tips.map((tip) => <div key={tip} className="row top small"><Lightbulb size={18} className="accent" style={{ flexShrink: 0 }} />{tip}</div>)}</Card>
          </>
        )}
      </div>
      <div className="bottom-action">
        <button className="btn-primary" onClick={() => { setup.select(recipe); navigate('/brew', true) }}><Droplet size={20} />Brew this</button>
      </div>
    </div>
  )
}

export function RecipeEditor({ recipeId, duplicate }: { recipeId: string; duplicate: boolean }) {
  const [draft, setDraft] = useState<Recipe>(() => {
    const base = allRecipes().find((r) => r.id === decodeURIComponent(recipeId))
    if (!base) return blankRecipe()
    if (duplicate) return { ...base, id: 'custom-' + newId(), name: base.isCustom ? `${base.name} copy` : `My ${base.name}`, isCustom: true }
    return base
  })
  const set = (patch: Partial<Recipe>) => setDraft((d) => ({ ...d, ...patch }))
  const setStep = (index: number, patch: Partial<RecipeStep>) =>
    setDraft((d) => ({ ...d, steps: d.steps.map((s, i) => (i === index ? { ...s, ...patch } : s)) }))

  const save = () => {
    repository.upsertRecipe(validatedRecipe({ ...draft, isCustom: true }))
    goBack('/recipes')
  }

  return (
    <div className="screen">
      <TopBar title={recipeId === 'new' || duplicate ? 'New recipe' : 'Edit recipe'} onBack={() => goBack('/recipes')}
        actions={<button className="link" style={{ padding: 8 }} onClick={save}>Save</button>} />
      <div className="content">
        <SectionHeader title="Recipe" />
        <Card>
          <TextInput label="Name" value={draft.name} onChange={(name) => set({ name })} />
          <TextInput label="Author" value={draft.author} onChange={(author) => set({ author })} />
          <div className="chips">{BREW_METHODS.map((m: BrewMethod) => <Chip key={m} title={METHOD_NAMES[m]} selected={draft.method === m} onClick={() => set({ method: m })} />)}</div>
        </Card>
        <SectionHeader title="Parameters" />
        <Card>
          <div className="row">
            <Field label="Coffee g"><NumberInput label="Coffee g" value={draft.dose} onChange={(v) => v != null && set({ dose: v })} min={1} max={150} /></Field>
            <Field label="Water g"><NumberInput label="Water g" value={draft.water} onChange={(v) => v != null && set({ water: v })} min={10} max={3000} decimals={0} /></Field>
            <Field label="Temp °C"><NumberInput label="Temp °C" value={draft.temperature} onChange={(v) => v != null && set({ temperature: v })} max={100} decimals={0} /></Field>
          </div>
          <Stepper label="Total time" value={mmss(draft.targetTime)} onMinus={() => set({ targetTime: Math.max(30, draft.targetTime - 5) })}
            onPlus={() => set({ targetTime: Math.min(1200, draft.targetTime + 5) })} />
          <div className="row">
            <Field label="Min pour g/s"><NumberInput label="Min pour g/s" value={draft.flowMin} onChange={(v) => v != null && set({ flowMin: v })} min={0.5} max={30} /></Field>
            <Field label="Max pour g/s"><NumberInput label="Max pour g/s" value={draft.flowMax} onChange={(v) => v != null && set({ flowMax: v })} min={1} max={40} /></Field>
          </div>
          <TextInput label="Grind description" value={draft.grind} onChange={(grind) => set({ grind })} max={200} />
        </Card>
        <SectionHeader title="Steps" />
        <Card>
          {draft.steps.map((step, i) => (
            <div key={i} style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {i > 0 && <div className="divider" />}
              <div className="row">
                <select className="input" style={{ width: 'auto', flex: 1 }} aria-label="Step action" value={step.kind}
                  onChange={(e) => setStep(i, { kind: e.target.value as RecipeStep['kind'] })}>
                  {STEP_KINDS.map((k) => <option key={k} value={k}>{STEP_TITLES[k]}</option>)}
                </select>
                <button className="icon-btn" aria-label="Delete step" onClick={() => set({ steps: draft.steps.filter((_, j) => j !== i) })}><Trash2 size={18} /></button>
              </div>
              <Stepper label="Starts at" value={mmss(step.time)} onMinus={() => setStep(i, { time: Math.max(0, step.time - 5) })}
                onPlus={() => setStep(i, { time: Math.min(1200, step.time + 5) })} />
              {isPour(step.kind) && (
                <Field label="Pour to (g total)"><NumberInput label="Pour to" value={step.target ?? 0} onChange={(v) => setStep(i, { target: v ?? 0 })} max={3000} decimals={0} /></Field>
              )}
              {isPour(step.kind) && draft.method === 'switch' && (
                <div className="chips">
                  <Chip title="Valve –" selected={!step.valve} onClick={() => setStep(i, { valve: null })} />
                  <Chip title="Open" selected={step.valve === 'open'} onClick={() => setStep(i, { valve: 'open' })} />
                  <Chip title="Closed" selected={step.valve === 'closed'} onClick={() => setStep(i, { valve: 'closed' })} />
                </div>
              )}
              <TextInput label="Note (optional)" value={step.note ?? ''} onChange={(note) => setStep(i, { note })} max={200} />
            </div>
          ))}
          <button className="btn" disabled={draft.steps.length >= 30} onClick={() => {
            const last = draft.steps[draft.steps.length - 1]
            const lastTarget = [...draft.steps].reverse().find((s) => isPour(s.kind))?.target ?? 0
            set({ steps: [...draft.steps, { kind: 'pour', time: (last?.time ?? -30) + 30, target: Math.min(lastTarget + 50, draft.water) }] })
          }}><Plus size={16} />Add step</button>
          <div className="small muted">Pour targets are cumulative scale weights. BrewLog pings a little before each target and chimes when each step starts.</div>
        </Card>
        <SectionHeader title="How it should taste" />
        <Card>
          <TextInput label="Taste description" value={draft.tasteNotes} onChange={(tasteNotes) => set({ tasteNotes })} max={2000} multiline />
          {(['acidity', 'sweetness', 'body', 'clarity'] as const).map((key) => (
            <Stepper key={key} label={key[0].toUpperCase() + key.slice(1)} value={String(draft.taste[key])}
              onMinus={() => set({ taste: { ...draft.taste, [key]: Math.max(1, draft.taste[key] - 1) } })}
              onPlus={() => set({ taste: { ...draft.taste, [key]: Math.min(5, draft.taste[key] + 1) } })} />
          ))}
          <TextInput label="Summary" value={draft.summary} onChange={(summary) => set({ summary })} max={2000} multiline />
        </Card>
      </div>
    </div>
  )
}
