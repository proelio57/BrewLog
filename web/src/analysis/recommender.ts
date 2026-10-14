import { type Bean, type Brew, type Equipment, type WeightSample, formatGrind } from '../domain/models'
import { type AnalysisInput, type BrewAnalysis, type GrinderContext, analyze } from './analyzer'

// Port of BrewAnalysis+Brew.swift / GrindRecommender.kt.

/** Earlier brews of the same bean on the same grinder, newest first. */
export function relatedHistory(brew: Brew, brews: Brew[]): Brew[] {
  if (brew.beanId == null) return []
  return brews
    .filter((b) => b.id !== brew.id && b.beanId === brew.beanId && b.grinderId === brew.grinderId && b.date < brew.date)
    .sort((a, b) => b.date - a.date)
}

/** Days off roast at the time of brewing. */
export const brewDaysOffRoast = (brew: Brew, bean: Bean | null): number | null =>
  bean?.roastDate != null ? Math.floor((brew.date - bean.roastDate) / 86_400_000) : null

export function analysisInput(brew: Brew, allBrews: Brew[], bean: Bean | null, samples: WeightSample[]): AnalysisInput | null {
  if (!brew.recipe) return null
  const grinder: GrinderContext | null = brew.grinderSpec
    ? { name: brew.grinderName || 'grinder', spec: brew.grinderSpec, currentValue: brew.grindValue }
    : null
  return {
    recipe: brew.recipe, samples, usedScale: brew.usedScale, totalTime: brew.totalTime, finalWeight: brew.finalWeight,
    dose: brew.dose, waterTemp: brew.waterTemp, roastLevel: bean?.roastLevel ?? null, daysOffRoast: brewDaysOffRoast(brew, bean),
    filterName: brew.filterName, filterFlow: brew.filterFlow, filterIdealRoast: brew.filterIdealRoast, grinder,
    feedback: brew.feedback,
    history: relatedHistory(brew, allBrews).map((b) => ({
      date: b.date, recipeId: b.recipeId, grindValue: b.grindValue, rating: b.rating, feedback: b.feedback, totalTime: b.totalTime,
    })),
  }
}

export function analyzeBrew(brew: Brew, allBrews: Brew[], bean: Bean | null, samples: WeightSample[]): BrewAnalysis | null {
  const input = analysisInput(brew, allBrews, bean, samples)
  return input ? analyze(input) : null
}

export interface GrindRecommendation { value: number; reason: string }

/** Picks a starting grind for the next brew from your own history. */
export function recommendGrind(beanId: string | null, grinder: Equipment | null, recipeId: string, brews: Brew[]): GrindRecommendation | null {
  if (!grinder) return null
  const spec = grinder.grinder
  const sameGrinder = brews.filter((b) => b.grinderId === grinder.id && b.grindValue != null).sort((a, b) => b.date - a.date)

  // Reference brew → its grind. Reviewed with a suggestion → the suggestion. Otherwise → last grind.
  const fromPool = (pool: Brew[], scope: string): GrindRecommendation | null => {
    const last = pool[0]
    if (!last || last.grindValue == null) return null
    if (last.feedback.includes('perfect') || last.rating >= 5) return { value: last.grindValue, reason: `Your reference brew ${scope}` }
    if (last.suggestedGrind != null && last.suggestedGrind !== last.grindValue) {
      return { value: last.suggestedGrind, reason: `Suggested after your last review ${scope} (${formatGrind(spec, last.grindValue)} → ${formatGrind(spec, last.suggestedGrind)})` }
    }
    const best = pool.filter((b) => b.rating >= 4).reduce<Brew | null>((top, b) => (top == null || b.rating > top.rating ? b : top), null)
    if (best?.grindValue != null) return { value: best.grindValue, reason: `Your best-rated brew ${scope} (${best.rating}★)` }
    return { value: last.grindValue, reason: `Your last brew ${scope}` }
  }

  if (beanId != null) {
    const sameBean = sameGrinder.filter((b) => b.beanId === beanId)
    const sameRecipe = sameBean.filter((b) => b.recipeId === recipeId)
    const result = fromPool(sameRecipe.length ? sameRecipe : sameBean, 'of this bean')
    if (result) return result
  }
  const result = fromPool(sameGrinder.filter((b) => b.recipeId === recipeId), 'of this recipe')
  if (result) return result
  const last = sameGrinder[0]
  return last?.grindValue != null ? { value: last.grindValue, reason: 'Your last brew on this grinder' } : null
}
