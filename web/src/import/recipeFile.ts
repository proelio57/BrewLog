import type { Recipe } from '../domain/recipe'
import { parseRecipe } from '../domain/validation'

// Port of RecipeFile.swift. A file holds one recipe, a list of recipes or { "recipes": [...] },
// the same JSON as Shared/recipes.json.

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)

/** Parses and validates the recipes in a file. Unknown entries are skipped; throws if none is left. */
export function decodeRecipes(value: unknown): Recipe[] {
  let list: unknown[]
  if (Array.isArray(value)) list = value
  else if (isObj(value) && Array.isArray(value.recipes)) list = value.recipes
  else if (isObj(value)) list = [value]
  else list = []
  const recipes = list.slice(0, 200).map(parseRecipe).filter((r): r is Recipe => r !== null)
  if (!recipes.length) throw new Error('No recipes found. A recipe file needs at least a "name" and "steps".')
  return recipes
}

/** One recipe as an object (reads nicely, can be pasted into recipes.json), several as a list. */
export function encodeRecipes(recipes: Recipe[]): string {
  return JSON.stringify(recipes.length === 1 ? recipes[0] : recipes, null, 2)
}

export function recipeFileName(recipes: Recipe[]): string {
  const base = recipes.length === 1 ? recipes[0].name : 'BrewLog recipes'
  const cleaned = base.replace(/[^\p{L}\p{N} _-]/gu, '').trim()
  return `${cleaned || 'Recipe'}.json`
}
