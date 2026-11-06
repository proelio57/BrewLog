package com.brewlog.app.domain

/**
 * Extraction yield from a refractometer reading (TDS): EY % = beverage (g) × TDS % / dose (g).
 * The beverage is what ends up in the cup, not the water poured: the grounds hold back about twice their dry weight.
 * Port of Extraction.swift.
 */
object Extraction {
    /** Water the spent grounds hold back, in grams per gram of coffee (pour-over). */
    const val RETENTION_RATIO = 2.0
    const val MAX_TDS = 25.0

    /** Extraction yield in percent, null when an input is missing. */
    fun yield(tds: Double, beverage: Double, dose: Double): Double? =
        if (tds > 0 && beverage > 0 && dose > 0) beverage * tds / dose else null

    /** Estimated drink weight when it wasn't weighed: the yield for espresso, the poured water minus what the grounds absorb for filter. */
    fun estimatedBeverage(finalWeight: Double, dose: Double, espresso: Boolean): Double = when {
        finalWeight <= 0 -> 0.0
        espresso -> finalWeight
        else -> maxOf(finalWeight - dose * RETENTION_RATIO, 0.0)
    }

    /** The classic brewing control chart zones (SCA / Gold Cup for filter, common espresso targets). */
    data class Zone(val tds: ClosedFloatingPointRange<Double>, val yield: ClosedFloatingPointRange<Double>) {
        companion object {
            val FILTER = Zone(1.15..1.45, 18.0..22.0)
            val ESPRESSO = Zone(8.0..12.0, 18.0..22.0)
            fun forMethod(espresso: Boolean) = if (espresso) ESPRESSO else FILTER
        }
    }

    enum class Verdict(val title: String) { UNDER("Under-extracted"), IDEAL("In the ideal range"), OVER("Over-extracted") }

    enum class Strength(val title: String) { WEAK("weak"), IDEAL("ideal strength"), STRONG("strong") }

    data class Reading(val tds: Double, val yield: Double, val verdict: Verdict, val strength: Strength) {
        /** Plain-language advice for the next brew. */
        val advice: String
            get() {
                val parts = mutableListOf<String>()
                when (verdict) {
                    Verdict.UNDER -> parts += "Extract more: grind finer, use hotter water or brew longer."
                    Verdict.OVER -> parts += "Extract less: grind coarser, use cooler water or brew shorter."
                    Verdict.IDEAL -> Unit
                }
                when (strength) {
                    Strength.WEAK -> parts += "For a stronger cup use more coffee for the same water (lower ratio)."
                    Strength.STRONG -> parts += "For a lighter cup use more water for the same coffee (higher ratio)."
                    Strength.IDEAL -> Unit
                }
                return if (parts.isEmpty()) "Balanced on both strength and extraction." else parts.joinToString(" ")
            }
    }

    fun evaluate(tds: Double, beverage: Double, dose: Double, espresso: Boolean): Reading? {
        val ey = yield(tds, beverage, dose) ?: return null
        val zone = Zone.forMethod(espresso)
        val verdict = when {
            ey < zone.yield.start -> Verdict.UNDER
            ey > zone.yield.endInclusive -> Verdict.OVER
            else -> Verdict.IDEAL
        }
        val strength = when {
            tds < zone.tds.start -> Strength.WEAK
            tds > zone.tds.endInclusive -> Strength.STRONG
            else -> Strength.IDEAL
        }
        return Reading(tds, ey, verdict, strength)
    }
}
