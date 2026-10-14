package com.brewlog.app.scale

import com.brewlog.app.domain.Recipe
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong
import kotlin.random.Random

/** Monotonic clock in milliseconds (shared by scale readings and the brew engine). */
fun monotonicMillis(): Long = System.nanoTime() / 1_000_000

/**
 * Simulates a scale that pours according to the recipe. Port of DemoScale in ScaleManager.swift.
 * Handy for trying the app without hardware or in the emulator.
 */
class DemoScale(private val scope: CoroutineScope, private val onWeight: (Double) -> Unit) {
    private data class PlannedPour(val start: Double, val goal: Double, val rate: Double)

    private var job: Job? = null
    private var weight = 0.0
    private var plan: List<PlannedPour> = emptyList()
    private var pourStart: Long? = null
    private var endTime = 0.0

    fun start() {
        if (job != null) return
        job = scope.launch {
            while (isActive) {
                tick()
                delay(100)
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        stopSimulation()
    }

    fun tare() {
        weight = 0.0
    }

    fun simulate(recipe: Recipe, delaySeconds: Double = 2.5) {
        weight = 0.0
        val low = max(recipe.flowMin, 2.0)
        val high = max(recipe.flowMax, low + 0.5)
        plan = recipe.pourSteps.mapIndexed { index, step ->
            PlannedPour(
                start = if (index == 0) 0.0 else step.time + Random.nextDouble(-1.0, 2.5),
                goal = (step.target ?: 0.0) + Random.nextDouble(-1.5, 2.5),
                rate = Random.nextDouble(low, high),
            )
        }
        endTime = recipe.targetTime + 20
        pourStart = monotonicMillis() + (delaySeconds * 1000).toLong()
    }

    fun stopSimulation() {
        plan = emptyList()
        pourStart = null
    }

    private fun tick() {
        val start = pourStart
        if (start != null) {
            val now = monotonicMillis()
            if (now >= start) {
                val t = (now - start) / 1000.0
                val active = plan.lastOrNull { it.start <= t }
                if (active != null && weight < active.goal) {
                    weight = min(active.goal, weight + active.rate * 0.1 * Random.nextDouble(0.75, 1.25))
                }
                if (t > endTime) stopSimulation()
            }
        }
        val noise = Random.nextDouble(-0.03, 0.03)
        onWeight(((weight + noise) * 10).roundToLong() / 10.0)
    }
}
