import { newId } from '../domain/format'
import { type AppData, type Bean, type Brew, type Equipment, defaultGrinderSpec } from '../domain/models'
import type { Recipe } from '../domain/recipe'
import { GRINDER_PRESETS } from '../domain/library'
import { LIMITS, clamped, sanitized } from '../domain/validation'
import {
  type BeanconquerorBackup, grindValueFrom, looksLikeBackup, methodFrom, parseBeanconqueror, processFrom, roastLevelFrom, stars,
} from './beanconqueror'
import { decodeRecipes } from './recipeFile'
import { isZip } from './zip'

// Port of DataImporter.swift: one "Import" for recipe files, Beanconqueror backups and BrewLog backups.
// The file type is detected from the contents. Pure functions on AppData, so they're easy to test.

export interface ImportSummary {
  recipesAdded: number
  recipesUpdated: number
  beans: number
  brewers: number
  grinders: number
  brews: number
  /** Brews that were already there (same id or same Beanconqueror brew). */
  skippedBrews: number
}

export const emptySummary = (): ImportSummary =>
  ({ recipesAdded: 0, recipesUpdated: 0, beans: 0, brewers: 0, grinders: 0, brews: 0, skippedBrews: 0 })

export function summaryMessage(s: ImportSummary): string {
  const parts: string[] = []
  const add = (count: number, singular: string, plural: string) => {
    if (count > 0) parts.push(`${count} ${count === 1 ? singular : plural}`)
  }
  add(s.recipesAdded, 'new recipe', 'new recipes')
  add(s.recipesUpdated, 'updated recipe', 'updated recipes')
  add(s.brews, 'brew', 'brews')
  add(s.beans, 'bean', 'beans')
  add(s.grinders, 'grinder', 'grinders')
  add(s.brewers, 'brewer', 'brewers')
  let text = parts.length ? `Imported ${parts.join(', ')}.` : 'Nothing new to import.'
  if (s.skippedBrews > 0) text += ` ${s.skippedBrews} ${s.skippedBrews === 1 ? 'brew was' : 'brews were'} already in your journal.`
  return text
}

export const MAX_FILE_SIZE = 200 * 1024 * 1024
const PREFIX = 'beanconqueror:'

/** What a file turned out to be, already parsed. */
export type ParsedImport =
  | { kind: 'recipes'; recipes: Recipe[] }
  | { kind: 'beanconqueror'; backup: BeanconquerorBackup }
  | { kind: 'brewlog'; backup: unknown }

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)

export async function parseImport(bytes: Uint8Array): Promise<ParsedImport> {
  if (bytes.length > MAX_FILE_SIZE) throw new Error('This file is too large to import.')
  if (isZip(bytes)) return { kind: 'beanconqueror', backup: await parseBeanconqueror(bytes) }
  let value: unknown
  try {
    value = JSON.parse(new TextDecoder().decode(bytes))
  } catch {
    throw new Error('No recipes found. A recipe file needs at least a "name" and "steps".')
  }
  if (looksLikeBackup(value)) return { kind: 'beanconqueror', backup: await parseBeanconqueror(bytes) }
  // BrewLog backup: {app: "BrewLog", data, samples} or the bare app data (older Android exports).
  if (isObj(value) && (value.app === 'BrewLog' || Array.isArray(value.brews) || Array.isArray(value.beans))) {
    return { kind: 'brewlog', backup: value }
  }
  return { kind: 'recipes', recipes: decodeRecipes(value) }
}

/** Adds the recipes as custom recipes. A built-in id becomes a copy; the same custom id updates it. */
export function importRecipes(data: AppData, recipes: Recipe[], presetIds: Set<string>): { data: AppData; summary: ImportSummary } {
  const summary = emptySummary()
  const custom = [...data.customRecipes]
  for (const original of recipes) {
    const recipe: Recipe = { ...original, isCustom: true }
    if (presetIds.has(recipe.id)) recipe.id = 'custom-' + newId()
    const index = custom.findIndex((r) => r.id === recipe.id)
    if (index >= 0) {
      custom[index] = recipe
      summary.recipesUpdated++
    } else {
      custom.push(recipe)
      summary.recipesAdded++
    }
  }
  return { data: { ...data, customRecipes: custom }, summary }
}

/** Beanconqueror brews, beans, grinders and brewers. Importing the same backup again only adds what's new. */
export function importBeanconqueror(data: AppData, backup: BeanconquerorBackup, now = Date.now()): { data: AppData; summary: ImportSummary } {
  const summary = emptySummary()
  const equipment = [...data.equipment]
  const beans = [...data.beans]
  const brews = [...data.brews]
  const importedBrews = new Set(brews.map((b) => b.externalId).filter(Boolean))
  const gear = new Map<string, Equipment>()
  const beanByKey = new Map<string, Bean>()
  // Imported gear and beans remember their Beanconqueror id, so a second import reuses them.
  for (const item of equipment) if (item.externalId) gear.set(item.externalId, item)
  for (const bean of beans) if (bean.externalId) beanByKey.set(bean.externalId, bean)

  const existing = (type: Equipment['type'], name: string) =>
    data.equipment.find((e) => e.type === type && e.name.toLowerCase() === name.toLowerCase())

  for (const mill of backup.mills) {
    const key = PREFIX + mill.uuid
    const name = sanitized(mill.name, LIMITS.maxNameLength)
    if (gear.has(key) || !name) continue
    const match = existing('grinder', name)
    if (match) { gear.set(key, match); continue }
    const preset = GRINDER_PRESETS.find((p) => name.toLowerCase().includes(p.name.toLowerCase())
      || (name.length >= 4 && p.name.toLowerCase().includes(name.toLowerCase())))
    const grinder: Equipment = {
      id: newId(), name, type: 'grinder', notes: sanitized(mill.note, LIMITS.maxLongText), method: null, filterFlow: null,
      idealRoast: null, grinder: preset?.grinder ?? defaultGrinderSpec(), createdAt: now, externalId: key,
    }
    equipment.push(grinder)
    gear.set(key, grinder)
    summary.grinders++
  }

  const usedPreparations = new Set(backup.brews.map((b) => b.preparationId))
  for (const preparation of backup.preparations) {
    if (preparation.finished && !usedPreparations.has(preparation.uuid)) continue
    const key = PREFIX + preparation.uuid
    const name = sanitized(preparation.name, LIMITS.maxNameLength)
    if (gear.has(key) || !name) continue
    const match = existing('brewer', name)
    if (match) { gear.set(key, match); continue }
    const brewer: Equipment = {
      id: newId(), name, type: 'brewer', notes: '', method: methodFrom(preparation.type), filterFlow: null, idealRoast: null,
      grinder: defaultGrinderSpec(), createdAt: now, externalId: key,
    }
    equipment.push(brewer)
    gear.set(key, brewer)
    summary.brewers++
  }

  for (const item of backup.beans) {
    const key = PREFIX + item.uuid
    if (beanByKey.has(key)) continue
    const bagWeight = item.weight > 0 ? clamped(item.weight, 1, LIMITS.maxBagWeight) : 250
    const used = backup.brews.filter((b) => b.beanId === item.uuid).reduce((sum, b) => sum + b.dose, 0)
    const bean: Bean = {
      id: newId(),
      name: sanitized(item.name, LIMITS.maxNameLength) || 'Imported beans',
      roaster: sanitized(item.roaster, LIMITS.maxNameLength),
      origin: [item.country, item.region].map((t) => sanitized(t, LIMITS.maxNameLength)).filter(Boolean).join(', '),
      varietal: sanitized(item.variety, LIMITS.maxNameLength),
      process: processFrom(item.processing) ?? 'washed',
      roastLevel: roastLevelFrom(item.roast) ?? 'light',
      roastDate: item.roastingDate,
      tastingNotes: sanitized(item.aromatics, LIMITS.maxShortText),
      notes: sanitized(item.note, LIMITS.maxLongText),
      bagWeight,
      remaining: item.finished ? 0 : Math.max(0, bagWeight - clamped(used, 0, LIMITS.maxBagWeight)),
      isArchived: item.finished,
      createdAt: item.roastingDate ?? now,
      externalId: key,
    }
    beans.push(bean)
    beanByKey.set(key, bean)
    summary.beans++
  }

  for (const item of backup.brews) {
    const key = PREFIX + item.uuid
    if (importedBrews.has(key)) {
      summary.skippedBrews++
      continue
    }
    const brewer = gear.get(PREFIX + item.preparationId) ?? null
    const grinder = gear.get(PREFIX + item.millId) ?? null
    // Espresso is measured in the cup (beverage weight), filter coffee by the water poured.
    const espresso = brewer?.method === 'espresso'
    const primary = espresso ? item.beverage : item.water
    const fallback = espresso ? item.water : item.beverage
    const water = clamped(primary > 0 ? primary : fallback, 0, LIMITS.maxWater)
    const brew: Brew = {
      id: newId(), date: item.date > 0 ? item.date : now, recipeId: 'beanconqueror', recipeName: brewer?.name ?? 'Beanconqueror',
      recipe: null, dose: clamped(item.dose, 0, LIMITS.maxDose), targetWater: water, finalWeight: water,
      totalTime: clamped(item.time, 0, LIMITS.maxBrewSeconds), waterTemp: clamped(item.temperature, 0, 100),
      grindSetting: sanitized(item.grindSize, LIMITS.maxShortText),
      grindValue: grinder ? grindValueFrom(item.grindSize) : null, suggestedGrind: null,
      brewerId: brewer?.id ?? null, brewerName: brewer?.name ?? '',
      grinderId: grinder?.id ?? null, grinderName: grinder?.name ?? '', grinderSpec: grinder?.grinder ?? null,
      filterId: null, filterName: '', filterFlow: null, filterIdealRoast: null,
      beanId: beanByKey.get(PREFIX + item.beanId)?.id ?? null, usedScale: false,
      rating: stars(backup, item.rating), feedback: [], notes: sanitized(item.note, LIMITS.maxLongText), externalId: key,
    }
    brews.push(brew)
    importedBrews.add(key)
    summary.brews++
  }

  return { data: { ...data, equipment, beans, brews }, summary }
}

/** Merges a BrewLog backup: adds what isn't there yet (by id), keeps everything that is. */
export function mergeAppData(data: AppData, incoming: AppData, presetIds: Set<string>): { data: AppData; summary: ImportSummary; newBrewIds: Set<string> } {
  const summary = emptySummary()
  const has = <T extends { id: string }>(list: T[]) => new Set(list.map((x) => x.id))
  const beanIds = has(data.beans)
  const gearIds = has(data.equipment)
  const brewIds = has(data.brews)
  const beans = [...data.beans]
  const equipment = [...data.equipment]
  const brews = [...data.brews]
  const newBrewIds = new Set<string>()
  for (const bean of incoming.beans) if (!beanIds.has(bean.id)) { beans.push(bean); summary.beans++ }
  for (const item of incoming.equipment) {
    if (gearIds.has(item.id)) continue
    equipment.push(item)
    if (item.type === 'grinder') summary.grinders++
    if (item.type === 'brewer') summary.brewers++
  }
  for (const brew of incoming.brews) {
    if (brewIds.has(brew.id)) { summary.skippedBrews++; continue }
    brews.push(brew)
    newBrewIds.add(brew.id)
    summary.brews++
  }
  const recipes = importRecipes({ ...data, beans, equipment, brews }, incoming.customRecipes, presetIds)
  summary.recipesAdded = recipes.summary.recipesAdded
  summary.recipesUpdated = recipes.summary.recipesUpdated
  return { data: recipes.data, summary, newBrewIds }
}
