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
}

@Serializable
enum class StepKind(val title: String) {
    @SerialName("bloom") BLOOM("Bloom"),
    @SerialName("pour") POUR("Pour"),
    @SerialName("swirl") SWIRL("Swirl"),
    @SerialName("stir") STIR("Stir"),
    @SerialName("closeValve") CLOSE_VALVE("Close valve"),
    @SerialName("openValve") OPEN_VALVE("Open valve"),
    @SerialName("remove") REMOVE("Remove dripper");

    val isPour: Boolean get() = this == BLOOM || this == POUR
}

@Serializable
enum class ValveState {
    @SerialName("open") OPEN,
    @SerialName("closed") CLOSED,
}

@Serializable
data class RecipeStep(
    val kind: StepKind,
    /** Start time in seconds from brew start. */
    val time: Double,
    /** Cumulative target weight in grams (pours/blooms only). */
    val target: Double? = null,
    /** Valve state for hybrid brewers like the Hario Switch. */
    val valve: ValveState? = null,
    val note: String? = null,
) {
    val headline: String
        get() = if (kind.isPour && target != null) {
            val verb = if (kind == StepKind.BLOOM) "Bloom to" else "Pour to"
            "$verb ${roundHalfAway(target).toLong()} g"
        } else {
            kind.title
        }
}

@Serializable
data class TasteProfile(val acidity: Int, val sweetness: Int, val body: Int, val clarity: Int)

@Serializable
data class Recipe(
    val id: String,
    val name: String,
    val author: String,
    val method: BrewMethod,
    val summary: String,
    /** Plain-language description of how the cup should taste. */
    val tasteNotes: String,
    val taste: TasteProfile,
    val dose: Double,
    val water: Double,
    val temperature: Double,
    val grind: String,
    /** Expected total brew time (incl. drawdown) in seconds. */
    val targetTime: Double,
    /** Healthy average pour rate range in g/s. */
    val flowMin: Double,
    val flowMax: Double,
    val steps: List<RecipeStep>,
    val tips: List<String>,
    val isCustom: Boolean? = null,
) {
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
