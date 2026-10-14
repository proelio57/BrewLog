package com.brewlog.app.domain

import kotlin.math.max
import kotlin.math.min

// Port of BrewLog/Recipes/RecipeValidation.swift.
// Everything the user types (or that is decoded from storage) is clamped to sane ranges,
// so corrupted or hostile data can never produce NaN timers, giant allocations or broken charts.

object InputLimits {
    const val MAX_NAME_LENGTH = 80
    const val MAX_SHORT_TEXT = 200
    const val MAX_LONG_TEXT = 2_000
    const val MAX_STEPS = 30
    const val MAX_TIPS = 20
    const val MAX_BREW_SECONDS = 1_800.0
    const val MAX_DOSE = 150.0
    const val MAX_WATER = 3_000.0
    const val MAX_BAG_WEIGHT = 10_000.0
}

/** Removes control/format characters (keeps newlines), trims whitespace and limits the length. */
fun String.sanitized(maxLength: Int): String {
    val cleaned = filter { c ->
        c == '\n' || !(Character.isISOControl(c) || Character.getType(c) == Character.FORMAT.toInt())
    }.trim()
    return if (cleaned.length > maxLength) cleaned.take(maxLength) else cleaned
}

/** Clamps to a range and maps NaN/∞ to the lower bound. */
fun Double.clamped(lower: Double, upper: Double): Double {
    if (!isFinite()) return lower
    if (lower > upper) return lower
    return coerceIn(lower, upper)
}

/** Returns a copy with every field sanitized and clamped to sane ranges. */
fun Recipe.validated(): Recipe {
    val cleanId = id.sanitized(120).ifEmpty { "custom-" + newId() }
    val cleanName = name.sanitized(InputLimits.MAX_NAME_LENGTH).ifEmpty { "Untitled recipe" }
    val cleanWater = water.clamped(10.0, InputLimits.MAX_WATER)
    val cleanFlowMin = flowMin.clamped(0.5, 30.0)
    val cleanFlowMax = flowMax.clamped(cleanFlowMin + 0.5, 40.0)

    val clampedSteps = steps.take(InputLimits.MAX_STEPS).map { step ->
        val effTarget = step.effectiveTarget
        val effNote = step.effectiveNote
        step.copy(
            time = step.time.clamped(0.0, InputLimits.MAX_BREW_SECONDS),
            target = if (step.kind.isPour) (effTarget ?: 0.0).clamped(0.0, cleanWater * 1.5) else null,
            note = effNote?.sanitized(InputLimits.MAX_SHORT_TEXT)?.ifEmpty { null },
        )
    }
    // Stable sort by time, then make cumulative pour targets non-decreasing.
    val sortedSteps = clampedSteps.withIndex()
        .sortedWith(compareBy({ it.value.time }, { it.index }))
        .map { it.value }
    var running = 0.0
    val cleanSteps = sortedSteps.map { step ->
        if (step.kind.isPour) {
            val target = max(step.target ?: 0.0, running)
            running = target
            step.copy(target = target)
        } else {
            step
        }
    }

    val lastStep = cleanSteps.lastOrNull()?.time ?: 0.0
    var cleanTargetTime = targetTime.clamped(10.0, InputLimits.MAX_BREW_SECONDS)
    if (cleanTargetTime < lastStep) cleanTargetTime = min(lastStep + 30, InputLimits.MAX_BREW_SECONDS)

    return copy(
        id = cleanId,
        name = cleanName,
        author = author.sanitized(InputLimits.MAX_NAME_LENGTH),
        summary = summary.sanitized(InputLimits.MAX_LONG_TEXT),
        tasteNotes = tasteNotes.sanitized(InputLimits.MAX_LONG_TEXT),
        grind = grind.sanitized(InputLimits.MAX_SHORT_TEXT),
        dose = dose.clamped(1.0, InputLimits.MAX_DOSE),
        water = cleanWater,
        temperature = temperature.clamped(0.0, 100.0),
        flowMin = cleanFlowMin,
        flowMax = cleanFlowMax,
        taste = TasteProfile(
            acidity = taste.acidity.coerceIn(1, 5),
            sweetness = taste.sweetness.coerceIn(1, 5),
            body = taste.body.coerceIn(1, 5),
            clarity = taste.clarity.coerceIn(1, 5),
        ),
        steps = cleanSteps,
        targetTime = cleanTargetTime,
        tips = tips.take(InputLimits.MAX_TIPS).map { it.sanitized(InputLimits.MAX_SHORT_TEXT) }.filter { it.isNotEmpty() },
    )
}
