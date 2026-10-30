package com.brewlog.app.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

// Port of BrewLog/Recipes/Recipe.swift. JSON field names are identical, so recipes.json is shared with iOS.

@Serializable
enum class BrewMethod(val displayName: String) {
    @SerialName("v60") V60("V60"),
    @SerialName("switch") HYBRID("Hario Switch"),
    @SerialName("kalita") KALITA("Flat bottom"),
    @SerialName("universal") UNIVERSAL("Any pour-over"),
    // Espresso recipes come with the shared recipes.json / online list (iOS has the full espresso mode).
    @SerialName("espresso") ESPRESSO("Espresso"),
}

@Serializable
enum class StepKind(val title: String) {
    @SerialName("bloom") BLOOM("Bloom"),
    @SerialName("pour") POUR("Pour"),
    @SerialName("swirl") SWIRL("Swirl"),
    @SerialName("stir") STIR("Stir"),
    @SerialName("closeValve") CLOSE_VALVE("Close valve"),
    @SerialName("openValve") OPEN_VALVE("Open valve"),
    @SerialName("remove") REMOVE("Remove dripper"),
    @SerialName("preinfuse") PREINFUSE("Pre-infusion"),
    @SerialName("extract") EXTRACT("Extract");

    val isPour: Boolean get() = this == BLOOM || this == POUR || this == EXTRACT
}

@Serializable
enum class ValveState {
    @SerialName("open") OPEN,
    @SerialName("closed") CLOSED,
}

@Serializable
data class RecipeStep(
    val kind: StepKind = StepKind.POUR,
    /** Start time in seconds from brew start. */
    val time: Double = 0.0,
    /** Cumulative target weight in grams (pours/blooms only). */
    val target: Double? = null,
    /** Valve state for hybrid brewers like the Hario Switch. */
    val valve: ValveState? = null,
    val note: String? = null,
    val water: Double? = null,
    val description: String? = null,
) {
    val effectiveTarget: Double? get() = target ?: water
    val effectiveNote: String? get() = note ?: description

    val headline: String
        get() = if (kind.isPour && effectiveTarget != null) {
            val verb = when (kind) {
                StepKind.BLOOM -> "Bloom to"
                StepKind.EXTRACT -> "Extract to"
                else -> "Pour to"
            }
            "$verb ${roundHalfAway(effectiveTarget!!).toLong()} g"
        } else {
            kind.title
        }
}

@Serializable
data class TasteProfile(
    val acidity: Int = 3,
    val sweetness: Int = 3,
    val body: Int = 3,
    val clarity: Int = 3,
)

@Serializable
data class Recipe(
    val id: String = newId(),
    val name: String = "",
    val author: String = "",
    val method: BrewMethod = BrewMethod.UNIVERSAL,
    val summary: String = "",
    /** Plain-language description of how the cup should taste. */
    val tasteNotes: String = "",
    val taste: TasteProfile = TasteProfile(),
    val dose: Double = 15.0,
    val water: Double = 250.0,
    val temperature: Double = 93.0,
    val grind: String = "",
    /** Expected total brew time (incl. drawdown) in seconds. */
    val targetTime: Double = 180.0,
    /** Healthy average pour rate range in g/s. */
    val flowMin: Double = 3.0,
    val flowMax: Double = 6.0,
    val steps: List<RecipeStep> = emptyList(),
    val tips: List<String> = emptyList(),
    val isCustom: Boolean? = null,
    /** Espresso: peak brew pressure in bar the recipe is designed for (e.g. 9, or 6 for turbo shots). */
    val pressure: Double? = null,
) {
    val isEspresso: Boolean get() = method == BrewMethod.ESPRESSO

    val ratio: Double get() = if (dose > 0) water / dose else 0.0

    val ratioText: String get() = "1:" + fmt1(ratio)

    val pourSteps: List<RecipeStep> get() = steps.filter { it.kind.isPour && it.target != null }

    /** Copy scaled to a new dose. Times stay the same; weights scale with the dose. */
    fun scaled(newDose: Double): Recipe {
        if (dose <= 0 || newDose <= 0 || abs(newDose - dose) <= 0.01) return this
        val factor = newDose / dose
        return copy(
            dose = newDose,
            water = roundHalfAway(water * factor),
            steps = steps.map { step ->
                val target = step.target
                if (target != null) step.copy(target = roundHalfAway(target * factor)) else step
            },
        )
    }

    /** Expected cumulative weight over time, used to draw the "ideal" line on charts. */
    fun targetCurve(): List<Pair<Double, Double>> {
        val points = mutableListOf(0.0 to 0.0)
        var previous = 0.0
        val idealFlow = max((flowMin + flowMax) / 2, 1.0)
        val pours = pourSteps
        pours.forEachIndexed { offset, step ->
            val target = step.target ?: return@forEachIndexed
            val nextStart = if (offset + 1 < pours.size) pours[offset + 1].time else targetTime
            var duration = (target - previous) / idealFlow
            duration = min(duration, max(nextStart - step.time - 1, 1.0))
            points.add(step.time to previous)
            points.add(step.time + duration to target)
            previous = target
        }
        points.add(targetTime to previous)
        return points
    }
}
