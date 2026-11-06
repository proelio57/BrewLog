package com.brewlog.app.brewing

import kotlin.math.max

/**
 * Decides during an espresso shot when to stop (just before the target yield, so the last drips land on it) and
 * when the shot is over (the weight has settled near the yield), and keeps the live numbers. Pure, so it is tested
 * without a scale or a machine; `BrewSession` feeds it the readings.
 * Port of Brewing/ShotMonitor.swift.
 */
class ShotMonitor(
    val yield: Double,
    val dose: Double,
    val stopLag: Double = 1.0,
    val autoStop: Boolean = true,
) {
    enum class Action {
        NONE, STOP, FINISH
    }

    data class Reading(val t: Double, val grams: Double)

    var firstDropsTime: Double? = null
        private set
    var stopped: Boolean = false
        private set
    var finished: Boolean = false
        private set
    private var lastGrams: Double = 0.0
    private val recent = mutableListOf<Reading>()

    /** The ratio so far (grams in the cup per gram of coffee), null before the first gram or without a dose. */
    val liveRatio: Double?
        get() {
            if (dose <= 0.0 || lastGrams < 1.0) return null
            return lastGrams / dose
        }

    fun ingest(grams: Double, flow: Double, t: Double): Action {
        if (!grams.isFinite() || !t.isFinite()) return Action.NONE
        lastGrams = grams
        if (firstDropsTime == null && grams >= 1.0) {
            firstDropsTime = t
        }
        recent.add(Reading(t, grams))
        recent.removeAll { t - it.t > SETTLE_WINDOW }

        if (autoStop && yield > 0.0 && !stopped && shouldStop(grams, flow, yield, stopLag)) {
            stopped = true
            return Action.STOP
        }
        if (yield > 0.0 && !finished && grams >= yield * FINISH_SHARE && isSettled(recent, t)) {
            finished = true
            return Action.FINISH
        }
        return Action.NONE
    }

    companion object {
        const val SETTLE_WINDOW: Double = 1.5
        const val SETTLE_TOLERANCE: Double = 0.3
        const val SETTLE_MINIMUM_READINGS: Int = 4
        const val FINISH_SHARE: Double = 0.9

        /**
         * Stop when the weight plus what is still on its way (flow * lag) reaches the yield. A negative flow (cup
         * bumped, scale noise) counts as none.
         */
        fun shouldStop(weight: Double, flow: Double, yield: Double, lag: Double): Boolean {
            return weight + max(flow, 0.0) * max(lag, 0.0) >= yield
        }

        /** Enough recent readings, all close together: nothing is dripping any more. */
        fun isSettled(readings: List<Reading>, now: Double): Boolean {
            val window = readings.filter { now - it.t <= SETTLE_WINDOW }.map { it.grams }
            if (window.size < SETTLE_MINIMUM_READINGS) return false
            val low = window.minOrNull() ?: return false
            val high = window.maxOrNull() ?: return false
            return (high - low) <= 2 * SETTLE_TOLERANCE
        }

        /**
         * The brew temperature to save: GaggiMate's target wins (the machine's settings are always right), then the
         * measured average, then the recipe. Implausible values (outside 70-105 °C) are skipped.
         */
        fun shotTemperature(recipe: Double, machineTarget: Double?, measuredAverage: Double?): Double {
            for (value in listOf(machineTarget, measuredAverage)) {
                if (value != null && value.isFinite() && value in 70.0..105.0) return value
            }
            return recipe
        }

        /** The pressure the shot is judged against: GaggiMate's target (1-15 bar) wins over the recipe's. */
        fun targetPressure(recipe: Double?, machineTarget: Double?): Double? {
            if (machineTarget != null && machineTarget.isFinite() && machineTarget in 1.0..15.0) return machineTarget
            return recipe
        }
    }
}
