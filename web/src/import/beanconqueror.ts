import type { ProcessMethod, RoastLevel } from '../domain/models'
import type { BrewMethod } from '../domain/recipe'
import { isZip, ZipArchive } from './zip'

// Port of BeanconquerorBackup.swift: Beanconqueror's export (Beanconqueror.zip or the older Beanconqueror.json),
// read leniently because the format changed over the years (numbers as strings, missing fields, nulls).

export interface BcBean {
  uuid: string; name: string; roaster: string; roastingDate: number | null; weight: number; roast: string
  note: string; aromatics: string; finished: boolean; country: string; region: string; variety: string; processing: string
}
export interface BcMill { uuid: string; name: string; note: string }
export interface BcPreparation { uuid: string; name: string; type: string; finished: boolean }
export interface BcBrew {
  uuid: string; date: number; grindSize: string; dose: number; preparationId: string; millId: string; beanId: string
  temperature: number; time: number; water: number; beverage: number; rating: number; note: string
}

export interface BeanconquerorBackup {
  beans: BcBean[]
  mills: BcMill[]
  preparations: BcPreparation[]
  brews: BcBrew[]
  /** Highest possible rating in the user's Beanconqueror settings (5 by default, can be 10 or 100). */
  ratingScale: number
}

export const MAIN_FILE_NAME = 'Beanconqueror.json'

type Obj = Record<string, unknown>
const isObj = (v: unknown): v is Obj => typeof v === 'object' && v !== null && !Array.isArray(v)
const objects = (v: unknown): Obj[] => (Array.isArray(v) ? v.filter(isObj) : [])

export const looksLikeBackup = (value: unknown): boolean => isObj(value) && ('BREWS' in value || 'BEANS' in value)

export function bcString(v: unknown): string {
  if (typeof v === 'string') return v
  if (typeof v === 'number' && Number.isFinite(v)) return String(v)
  return ''
}

/** Numeric grind setting ("24", "7,5", "2.1") or null for free text like "medium-fine". */
export function grindValueFrom(text: string): number | null {
  const cleaned = text.trim().replace(',', '.')
  if (!cleaned || !/^[0-9]+(\.[0-9]+)?$/.test(cleaned)) return null
  const value = Number(cleaned)
  return Number.isFinite(value) && value >= 0 ? value : null
}

export function bcNumber(v: unknown): number | null {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null
  if (typeof v === 'string') return grindValueFrom(v)
  return null
}

const bool = (v: unknown): boolean => v === true || v === 1 || (typeof v === 'string' && v.toLowerCase() === 'true')

/** ISO 8601 with or without fractional seconds, or a plain date. */
export function bcDate(v: unknown): number | null {
  const text = bcString(v).trim()
  if (!text) return null
  const time = Date.parse(text)
  return Number.isFinite(time) ? time : null
}

const uuid = (item: Obj): string | null => {
  const value = bcString(isObj(item.config) ? item.config.uuid : undefined)
  return value || null
}

export function parseBackupObject(dict: Obj): BeanconquerorBackup {
  const settingsList = Array.isArray(dict.SETTINGS) ? dict.SETTINGS : [dict.SETTINGS]
  const settings = settingsList.find(isObj)
  const scale = settings ? bcNumber(settings.brew_rating) : null

  const beans: BcBean[] = []
  for (const item of objects(dict.BEANS)) {
    const id = uuid(item)
    if (!id) continue
    const info = objects(item.bean_information)[0] ?? {}
    beans.push({
      uuid: id, name: bcString(item.name), roaster: bcString(item.roaster), roastingDate: bcDate(item.roastingDate),
      weight: bcNumber(item.weight) ?? 0, roast: bcString(item.roast), note: bcString(item.note),
      aromatics: bcString(item.aromatics), finished: bool(item.finished), country: bcString(info.country),
      region: bcString(info.region), variety: bcString(info.variety), processing: bcString(info.processing),
    })
  }
  const mills: BcMill[] = []
  for (const item of objects(dict.MILL)) {
    const id = uuid(item)
    if (id) mills.push({ uuid: id, name: bcString(item.name), note: bcString(item.note) })
  }
  const preparations: BcPreparation[] = []
  for (const item of objects(dict.PREPARATION)) {
    const id = uuid(item)
    if (id) preparations.push({ uuid: id, name: bcString(item.name), type: bcString(item.type), finished: bool(item.finished) })
  }
  const brews: BcBrew[] = []
  for (const item of objects(dict.BREWS)) {
    const id = uuid(item)
    if (!id) continue
    const config = isObj(item.config) ? item.config : {}
    brews.push({
      uuid: id,
      date: (bcNumber(config.unix_timestamp) ?? 0) * 1000,
      grindSize: bcString(item.grind_size), dose: bcNumber(item.grind_weight) ?? 0,
      preparationId: bcString(item.method_of_preparation), millId: bcString(item.mill), beanId: bcString(item.bean),
      temperature: bcNumber(item.brew_temperature) ?? 0,
      time: (bcNumber(item.brew_time) ?? 0) + (bcNumber(item.brew_time_milliseconds) ?? 0) / 1000,
      water: bcNumber(item.brew_quantity) ?? 0, beverage: bcNumber(item.brew_beverage_quantity) ?? 0,
      rating: bcNumber(item.rating) ?? 0, note: bcString(item.note),
    })
  }
  return { beans, mills, preparations, brews, ratingScale: scale != null && scale > 0 ? scale : 5 }
}

/** Parses a ZIP export or a plain JSON export. */
export async function parseBeanconqueror(bytes: Uint8Array): Promise<BeanconquerorBackup> {
  if (isZip(bytes)) {
    const zip = new ZipArchive(bytes)
    const mainEntry = zip.entry(MAIN_FILE_NAME)
    if (!mainEntry) throw new Error("The ZIP file doesn't contain a Beanconqueror.json.")
    const main = JSON.parse(await zip.text(mainEntry)) as unknown
    if (!isObj(main)) throw new Error("This file isn't a Beanconqueror backup.")
    // Large backups are split: the first chunk is in the main file, the rest in Beanconqueror_<Name>_<n>.json.
    for (const [key, fileName] of [['BREWS', 'Brews'], ['BEANS', 'Beans']] as const) {
      const items: unknown[] = Array.isArray(main[key]) ? [...(main[key] as unknown[])] : []
      for (let index = 1; ; index++) {
        const entry = zip.entry(`Beanconqueror_${fileName}_${index}.json`)
        if (!entry) break
        const chunk = JSON.parse(await zip.text(entry)) as unknown
        if (Array.isArray(chunk)) items.push(...chunk)
      }
      main[key] = items
    }
    return parseBackupObject(main)
  }
  let value: unknown
  try {
    value = JSON.parse(new TextDecoder().decode(bytes))
  } catch {
    throw new Error("This file isn't a Beanconqueror backup.")
  }
  if (!looksLikeBackup(value)) throw new Error("This file isn't a Beanconqueror backup.")
  return parseBackupObject(value as Obj)
}

// MARK: Mapping helpers (same rules as iOS and Android)

/** Rating on Beanconqueror's scale → BrewLog's 0–5 stars (0 = not rated). */
export function stars(backup: BeanconquerorBackup, rating: number): number {
  if (!(rating > 0) || !(backup.ratingScale > 0)) return 0
  return Math.round(Math.min(Math.max((rating / backup.ratingScale) * 5, 1), 5))
}

export function roastLevelFrom(roast: string): RoastLevel | null {
  switch (roast.toLowerCase()) {
    case 'cinnamon roast': case 'new england roast': case 'half city roast': return 'light'
    case 'american roast': case 'moderate-light roast': return 'mediumLight'
    case 'city roast': case 'city+ roast': return 'medium'
    case 'full city roast': case 'full city + roast': return 'mediumDark'
    case 'vienna roast': case 'french roast': case 'italian roast': return 'dark'
    default: return null
  }
}

export function processFrom(text: string): ProcessMethod | null {
  const lower = text.toLowerCase()
  if (!lower) return null
  if (lower.includes('anaerob')) return 'anaerobic'
  if (lower.includes('honey')) return 'honey'
  if (lower.includes('natur') || lower.includes('dry')) return 'natural'
  if (lower.includes('wash') || lower.includes('gewaschen')) return 'washed'
  return 'other'
}

export function methodFrom(type: string): BrewMethod | null {
  switch (type.toUpperCase()) {
    case 'V60': case 'ORIGAMI': case 'KONO': case 'CAFEC_FLOWER': case 'HARIO_WOODNECK': case 'TORNADO_DUO': return 'v60'
    case 'HARIO_SWITCH': case 'CLEVER': return 'switch'
    case 'KALITA_WAVE': case 'OREA': case 'APRIL_BREWER': case 'DECEMBER_DRIPPER': case 'BLUE_DRIPPER': case 'XBLOOM': return 'kalita'
    case 'CHEMEX': case 'DRIPPER': case 'RATIO_SIX_COFFEE_BREWER': case 'MOCCA_MASTER': return 'universal'
    case 'PORTAFILTER': case 'GAGGIMATE': case 'GAGGIUINO': case 'METICULOUS': case 'XENIA': case 'SANREMO_YOU':
    case 'DECENT_ESPRESSO': case 'MOVE2': case 'HAND_LEVER': case 'FLAIR': case 'CAFELAT': case 'ROK': return 'espresso'
    default: return null
  }
}
