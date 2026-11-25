package com.brewlog.app.domain

import kotlin.math.max

/**
 * A brew that was probably started or stopped by mistake: very short, or hardly any weight in the cup.
 * The rating screen then highlights "Discard brew".
 */
enum class BrewMistake {
    TOO_SHORT, TOO_LITTLE;

    companion object {
        /** Shorter than this is no shot (espresso). */
        const val MIN_ESPRESSO_SECONDS = 8.0
        /** Shorter than this is no pour-over. */
        const val MIN_POUR_OVER_SECONDS = 30.0

        /** What looks wrong about the brew, or null when it looks like a real one. The weight only counts with a scale. */
        fun check(isEspresso: Boolean, usedScale: Boolean, totalTime: Double, finalWeight: Double, targetWater: Double): BrewMistake? {
            if (totalTime < (if (isEspresso) MIN_ESPRESSO_SECONDS else MIN_POUR_OVER_SECONDS)) return TOO_SHORT
            if (usedScale && finalWeight < max(2.0, targetWater * 0.15)) return TOO_LITTLE
            return null
        }
    }
}
