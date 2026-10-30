package com.brewlog.app.brewing

import com.brewlog.app.domain.InputLimits
import kotlin.math.roundToLong

/** Weighing the beans before a brew. Port of BeanDosing.swift. */
object BeanDosing {
    enum class Status { EMPTY, UNDER, ON_TARGET, OVER }

    /** ±0.2 g counts as on target: the scale shows 0.1 g and a single bean weighs about 0.15 g. */
    const val TOLERANCE = 0.2

    fun status(weight: Double, dose: Double): Status = when {
        !weight.isFinite() || weight < 0.5 -> Status.EMPTY
        weight < dose - TOLERANCE -> Status.UNDER
        weight > dose + TOLERANCE -> Status.OVER
        else -> Status.ON_TARGET
    }

    /** 0…1 for the progress bar. */
    fun progress(weight: Double, dose: Double): Double =
        if (dose <= 0 || !weight.isFinite()) 0.0 else (weight / dose).coerceIn(0.0, 1.0)

    /** The dose to save with the brew: what was weighed (to 0.1 g), or the planned dose when the reading is implausible. */
    fun acceptedDose(weight: Double, planned: Double): Double =
        if (!weight.isFinite() || weight < 0.5 || weight > InputLimits.MAX_DOSE) planned else (weight * 10).roundToLong() / 10.0

    /** Below this difference the recipe stays as planned; from here on it is scaled to the weighed dose. */
    const val RESCALE_THRESHOLD = 0.5

    /** The recipe for the weighed dose: scaled (water and pour targets) when it is at least 0.5 g off the plan. */
    fun recipe(recipe: com.brewlog.app.domain.Recipe, dose: Double): com.brewlog.app.domain.Recipe =
        if (kotlin.math.abs(dose - recipe.dose) >= RESCALE_THRESHOLD) recipe.scaled(dose) else recipe

    /**
     * A settled reading: the readings of the last second (at least 4) lie within ±0.2 g. Lifting the cup off or
     * still pouring beans in doesn't count, so "Ready" keeps what was actually weighed. [readings]: (ms, grams).
     */
    fun stableWeight(readings: Collection<Pair<Long, Double>>, nowMs: Long): Double? {
        val window = readings.filter { nowMs - it.first <= 1_000 }.map { it.second }
        if (window.size < 4 || window.max() - window.min() > 2 * TOLERANCE) return null
        val mean = window.average()
        return if (status(mean, 1.0) == Status.EMPTY) null else mean
    }
}
