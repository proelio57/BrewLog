package com.brewlog.app.domain

/** Filters recipes by brewer type and picks alternatives. Port of RecipeFilter.swift. */
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

    data class Section(val title: String, val recipes: List<Recipe>)

    /** "My recipes" first, then the built-in recipes grouped by method; the filtered method's group comes first. */
    fun sections(custom: List<Recipe>, presets: List<Recipe>, method: BrewMethod?): List<Section> {
        val result = ArrayList<Section>()
        val mine = custom.filter { matches(it, method) }
        if (mine.isNotEmpty()) result += Section("My recipes", mine)
        val order = BrewMethod.entries.toMutableList()
        if (method != null) { order.remove(method); order.add(0, method) }
        for (group in order) {
            val recipes = presets.filter { it.method == group && matches(it, method) }
            if (recipes.isNotEmpty()) result += Section(group.displayName, recipes)
        }
        return result
    }

    /** The methods that have recipes, for the filter chips. "Any pour-over" isn't a brewer: its recipes show under every pour-over filter. */
    fun methods(recipes: List<Recipe>): List<BrewMethod> {
        val present = recipes.map { it.method }.toSet()
        return BrewMethod.entries.filter { it in present && it != BrewMethod.UNIVERSAL }
    }
}

/**
 * The valve position a step switches to (Hario Switch and similar), null when the valve stays as it is.
 * The position at the start of the brew isn't a change. Port of Recipe.valveChange(at:).
 */
fun Recipe.valveChange(index: Int): ValveState? {
    if (index !in steps.indices || index == 0 || steps[index].time <= 0) return null
    val target = valveOf(steps[index]) ?: return null
    val previous = steps.subList(0, index).asReversed().firstNotNullOfOrNull(::valveOf)
    return if (previous == target) null else target
}

private fun valveOf(step: RecipeStep): ValveState? = when (step.kind) {
    StepKind.CLOSE_VALVE -> ValveState.CLOSED
    StepKind.OPEN_VALVE -> ValveState.OPEN
    else -> step.valve
}
