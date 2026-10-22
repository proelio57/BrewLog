package com.brewlog.app.domain

/** Port of RecipeFilter.swift (the part the analysis needs). */
object RecipeFilter {
    /** Whether a recipe fits a brewer of this type. "Any pour-over" recipes fit every pour-over brewer. */
    fun matches(recipe: Recipe, method: BrewMethod?): Boolean {
        if (method == null || recipe.method == method) return true
        return method != BrewMethod.ESPRESSO && recipe.method == BrewMethod.UNIVERSAL
    }

    /**
     * A recipe for the same brewer that brings more clarity, for "flat" cups. Never the recipe that was just
     * brewed (also not a copy of it under the same name), never a template, and never an espresso recipe.
     */
    fun clearerAlternative(recipe: Recipe, candidates: List<Recipe>): Recipe? {
        if (recipe.method == BrewMethod.ESPRESSO) return null
        val minimum = maxOf(recipe.taste.clarity, 4)
        var best: Recipe? = null
        for (candidate in candidates) {
            if (candidate.id == recipe.id || candidate.id.startsWith("template-")) continue
            if (candidate.name.equals(recipe.name, ignoreCase = true)) continue
            if (candidate.method == BrewMethod.ESPRESSO) continue
            if (recipe.method != BrewMethod.UNIVERSAL && !matches(candidate, recipe.method)) continue
            if (candidate.taste.clarity < minimum) continue
            // Clearest first, then the sweeter one, then library order.
            val current = best
            if (current == null || candidate.taste.clarity > current.taste.clarity ||
                (candidate.taste.clarity == current.taste.clarity && candidate.taste.sweetness > current.taste.sweetness)
            ) best = candidate
        }
        return best
    }
}
