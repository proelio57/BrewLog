package com.brewlog.app.domain

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlin.math.max

/**
 * Learns how long coffee keeps arriving after BrewLog stops a shot, so the next stop lands on the yield.
 * What arrived after the stop divided by the flow at the stop is the lead that would have been right; the stored
 * lead moves halfway towards it. Kept per machine and scale. Port of Brewing/StopLagLearner.swift.
 */
object StopLagLearner {
    const val MIN_LAG = 0.3
    const val MAX_LAG = 3.0
    const val MIN_FLOW = 0.5
    const val LEARNING_RATE = 0.5

    @Serializable
    data class Learned(val lag: Double, val shots: Int)

    fun measuredLag(weightAtStop: Double, flowAtStop: Double, finalWeight: Double): Double? {
        if (!weightAtStop.isFinite() || !flowAtStop.isFinite() || !finalWeight.isFinite() || flowAtStop < MIN_FLOW) return null
        val after = finalWeight - weightAtStop
        if (after < -0.5 || after > flowAtStop * 5) return null
        return (max(after, 0.0) / flowAtStop).coerceIn(MIN_LAG, MAX_LAG)
    }

    fun updated(current: Double, measured: Double): Double =
        (current + LEARNING_RATE * (measured - current)).coerceIn(MIN_LAG, MAX_LAG)

    /** "gaggimate-phone" or "gaggimate-machine": where the weight comes from changes the delay. */
    fun key(machine: String, scaleOnMachine: Boolean): String = "$machine-${if (scaleOnMachine) "machine" else "phone"}"

    /** One more shot on top of [previous]; null when the shot can't teach anything. */
    fun next(previous: Learned?, start: Double, weightAtStop: Double, flowAtStop: Double, finalWeight: Double): Learned? {
        val measured = measuredLag(weightAtStop, flowAtStop, finalWeight) ?: return null
        return Learned(updated(previous?.lag ?: start, measured), (previous?.shots ?: 0) + 1)
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val mapSerializer = MapSerializer(String.serializer(), Learned.serializer())

    fun decode(text: String?): Map<String, Learned> =
        text?.let { runCatching { json.decodeFromString(mapSerializer, it) }.getOrNull() } ?: emptyMap()

    fun encode(all: Map<String, Learned>): String = json.encodeToString(mapSerializer, all)
}
