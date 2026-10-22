import type { BrewMethod, Recipe } from './recipe'

// Port of RecipeFilter.swift (the part the analysis needs).

/** Whether a recipe fits a brewer of this type. "Any pour-over" recipes fit every pour-over brewer. */
export function matchesMethod(recipe: Recipe, method: BrewMethod | null): boolean {
  if (method == null) return true
  if (recipe.method === method) return true
  return method !== 'espresso' && recipe.method === 'universal'
}

/**
 * A recipe for the same brewer that brings more clarity, for "flat" cups. Never the recipe that was just
 * brewed (also not a copy of it under the same name), never a template, and never an espresso recipe.
 */
export function clearerAlternative(recipe: Recipe, candidates: Recipe[]): Recipe | null {
  if (recipe.method === 'espresso') return null
  const minimum = Math.max(recipe.taste.clarity, 4)
  const name = recipe.name.toLowerCase()
  let best: Recipe | null = null
  for (const candidate of candidates) {
    if (candidate.id === recipe.id || candidate.name.toLowerCase() === name || candidate.id.startsWith('template-')) continue
    if (candidate.method === 'espresso') continue
    if (recipe.method !== 'universal' && !matchesMethod(candidate, recipe.method)) continue
    if (candidate.taste.clarity < minimum) continue
    // Clearest first, then the sweeter one, then library order.
    if (!best || candidate.taste.clarity > best.taste.clarity
      || (candidate.taste.clarity === best.taste.clarity && candidate.taste.sweetness > best.taste.sweetness)) best = candidate
  }
  return best
}
