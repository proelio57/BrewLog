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
}
