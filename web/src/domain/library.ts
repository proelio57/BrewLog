import { newId } from './format'
import { type Equipment, type EquipmentType, type FilterFlow, type GrindUnit, type GrinderSpec, type PaperShape, type RoastLevel, defaultGrinderSpec } from './models'
import type { BrewMethod, Recipe } from './recipe'
import { parseRecipe } from './validation'
import recipesJson from '../../../Shared/recipes.json'

// Port of RecipeLibrary.swift / Library.kt.

/** Built-in recipes: the same Shared/recipes.json as iOS and Android (validated). Kept up to date by the online list. */
export const PRESET_RECIPES: Recipe[] = (recipesJson as unknown[]).map(parseRecipe).filter((r): r is Recipe => r !== null)

export function blankRecipe(): Recipe {
  return {
    id: 'custom-' + newId(), name: 'My Recipe', author: 'Me', method: 'v60', summary: '', tasteNotes: '',
    taste: { acidity: 3, sweetness: 3, body: 3, clarity: 3 },
    dose: 15, water: 250, temperature: 94, grind: 'Medium-fine', targetTime: 180, flowMin: 3, flowMax: 8,
    steps: [
      { kind: 'bloom', time: 0, target: 45 },
      { kind: 'pour', time: 45, target: 150 },
      { kind: 'pour', time: 75, target: 250 },
    ],
    tips: [],
    isCustom: true,
  }
}

export interface EquipmentPreset {
  name: string
  type: EquipmentType
  method?: BrewMethod
  flow?: FilterFlow
  idealRoast?: RoastLevel
  grinder?: GrinderSpec
  notes?: string
  /** Paper shape a brewer takes / a filter has (used to show compatible papers first). */
  shape?: PaperShape
}

export function makeEquipment(preset: EquipmentPreset): Equipment {
  return {
    id: newId(), name: preset.name, type: preset.type, notes: preset.notes ?? '',
    method: preset.method ?? null, filterFlow: preset.flow ?? null, idealRoast: preset.idealRoast ?? null,
    grinder: preset.grinder ?? defaultGrinderSpec(), createdAt: Date.now(),
  }
}

const grinder = (name: string, unit: GrindUnit, step: number, adjust: number, range = '', notes = ''): EquipmentPreset =>
  ({ name, type: 'grinder', grinder: { unit, step, adjustStep: adjust, finerIsLower: true, rangeNote: range }, notes })

/** Grinder scales. Ranges are typical starting points only, so they're editable. */
export const GRINDER_PRESETS: EquipmentPreset[] = [
  grinder('Comandante C40', 'clicks', 1, 2, '20–30 clicks', 'Clicks counted from fully closed. About 30 µm per click.'),
  grinder('1Zpresso K-Ultra', 'numbers', 0.1, 0.2, '', 'Read the dial as rotation.number, e.g. 7.5.'),
  grinder('1Zpresso ZP6 Special', 'numbers', 0.1, 0.2, '', 'Read the dial as rotation.number, e.g. 4.5.'),
  grinder('1Zpresso J-Max', 'clicks', 1, 5, '', 'Very fine steps, so adjust in bigger jumps for filter.'),
  grinder('Timemore C3', 'clicks', 1, 1, 'about 14–20 clicks'),
  grinder('Kingrinder K6', 'clicks', 1, 5, '', 'Fine steps, so adjust in bigger jumps for filter.'),
  grinder('Fellow Ode Gen 2', 'dial', 1, 1, '', 'Dial 1–11 in steps of 1/3. Track whole numbers or enter thirds as decimals.'),
  grinder('Baratza Encore ESP', 'numbers', 1, 2),
  grinder('Niche Zero', 'dial', 1, 3),
  grinder('Wilfa Uniform', 'numbers', 1, 1),
  grinder('Lagom P64', 'dial', 0.1, 0.2),
  grinder('Mazzer Philos', 'dial', 1, 2),
  grinder('DF64 / DF83', 'dial', 1, 3),
]

/** CAFEC roast-specific papers are named after their recommended brew temperature. */
export const FILTER_PRESETS: EquipmentPreset[] = [
  { name: 'CAFEC T-90 (Medium-Dark Roast)', type: 'filter', flow: 'medium', idealRoast: 'mediumDark', shape: 'cone',
    notes: 'Two-sided crepe, smooth and steady flow, designed for 90 °C. Balanced and repeatable. Also popular for light roasts.' },
  { name: 'CAFEC T-92 (Light Roast)', type: 'filter', flow: 'fast', idealRoast: 'light', shape: 'cone',
    notes: 'Low density with a deep crepe, designed for 92 °C. Clean cup with strong aroma.' },
  { name: 'CAFEC T-83 (Dark Roast)', type: 'filter', flow: 'medium', idealRoast: 'dark', shape: 'cone',
    notes: '0.22 mm, medium density, designed for 83 °C. Fast at first, then slows down. Brings body and sweetness.' },
  { name: 'CAFEC Abaca+', type: 'filter', flow: 'fast', shape: 'cone', notes: 'Abaca fibre blend. Fast flow, great clarity, an all-rounder.' },
  { name: 'CAFEC Abaca', type: 'filter', flow: 'fast', shape: 'cone', notes: 'The original abaca paper. Fast and clean.' },
  { name: 'Hario V60 standard paper', type: 'filter', flow: 'medium', shape: 'cone', notes: 'The standard white V60 paper. Medium flow. Rinse well.' },
  { name: 'Hario V60 tabbed paper (Japan)', type: 'filter', flow: 'fast', shape: 'cone', notes: 'Japanese-made tabbed paper. Faster than the standard paper.' },
  { name: 'Hario V60 natural paper (unbleached)', type: 'filter', flow: 'medium', shape: 'cone', notes: 'Unbleached brown paper. Rinse very well to avoid a papery taste.' },
  { name: 'Sibarist FAST Cone', type: 'filter', flow: 'fast', shape: 'cone', notes: 'Very fast specialty paper. Lets you grind finer without stalling.' },
  { name: 'Origami cone paper', type: 'filter', flow: 'fast', shape: 'cone' },
  { name: 'Kalita Wave 185 paper', type: 'filter', flow: 'medium', shape: 'flat', notes: 'Flat-bottom wave paper for Kalita, Orea and similar drippers.' },
  { name: 'Sibarist FAST Flat', type: 'filter', flow: 'fast', shape: 'flat', notes: 'Flat-bottom version for Orea, April and Kalita.' },
  { name: 'Chemex bonded paper', type: 'filter', flow: 'slow', shape: 'chemex', notes: 'Thick paper, very clean cup with lighter body. Slow drawdown, so grind coarser.' },
]

export const BREWER_PRESETS: EquipmentPreset[] = [
  { name: 'Hario V60 02', type: 'brewer', method: 'v60', shape: 'cone' },
  { name: 'Hario V60 01', type: 'brewer', method: 'v60', shape: 'cone' },
  { name: 'Hario Switch 02', type: 'brewer', method: 'switch', shape: 'cone' },
  { name: 'Hario Switch 03', type: 'brewer', method: 'switch', shape: 'cone' },
  { name: 'Kalita Wave 185', type: 'brewer', method: 'kalita', shape: 'flat' },
  { name: 'Origami Dripper M', type: 'brewer', method: 'v60', shape: 'cone' },
  { name: 'Orea v4', type: 'brewer', method: 'kalita', shape: 'flat' },
  { name: 'April Brewer', type: 'brewer', method: 'kalita', shape: 'flat' },
  { name: 'Chemex 6-cup', type: 'brewer', method: 'universal', shape: 'chemex' },
  { name: 'Clever Dripper', type: 'brewer', method: 'switch', shape: 'cone' },
  // Espresso machines
  { name: 'Gaggia Classic (GaggiMate)', type: 'brewer', method: 'espresso', notes: 'Connect it in Settings → Espresso machine for pressure curves and shot control.' },
  { name: 'Gaggia Classic', type: 'brewer', method: 'espresso' },
  { name: 'Rancilio Silvia', type: 'brewer', method: 'espresso' },
  { name: 'Lelit Bianca', type: 'brewer', method: 'espresso' },
  { name: 'La Marzocco Linea Micra', type: 'brewer', method: 'espresso' },
  { name: 'La Marzocco Linea Mini', type: 'brewer', method: 'espresso' },
  { name: 'Breville / Sage Barista', type: 'brewer', method: 'espresso' },
  { name: 'Decent DE1', type: 'brewer', method: 'espresso' },
  { name: 'Flair 58', type: 'brewer', method: 'espresso' },
]

const OTHER_PRESETS: EquipmentPreset[] = [
  { name: 'Fellow Stagg EKG', type: 'kettle' },
  { name: 'Hario Buono', type: 'kettle' },
  { name: 'Brewista Artisan', type: 'kettle' },
  { name: 'Bookoo Themis Mini', type: 'scale' },
  { name: 'Third Wave Water (light roast)', type: 'water' },
  { name: 'Filtered tap water', type: 'water' },
]

export const ALL_PRESETS: EquipmentPreset[] = [...FILTER_PRESETS, ...GRINDER_PRESETS, ...BREWER_PRESETS, ...OTHER_PRESETS]

/** Defaults for a custom grinder in the setup assistant. */
export function specFor(unit: GrindUnit): GrinderSpec {
  switch (unit) {
    case 'clicks': return { unit, step: 1, adjustStep: 2, finerIsLower: true, rangeNote: '' }
    case 'numbers': return { unit, step: 1, adjustStep: 1, finerIsLower: true, rangeNote: '' }
    case 'dial': return { unit, step: 0.1, adjustStep: 0.2, finerIsLower: true, rangeNote: '' }
    case 'microns': return { unit, step: 10, adjustStep: 50, finerIsLower: true, rangeNote: '' }
  }
}
