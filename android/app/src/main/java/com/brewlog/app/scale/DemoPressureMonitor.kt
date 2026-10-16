package com.brewlog.app.scale

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong
import kotlin.random.Random

/**
 * Simulates a BOOKOO Espresso Monitor for testing espresso pressure profiling without hardware.
 * Emits realistic extraction pressure curves (pre-infusion, 9 bar peak, pressure decline).
 */
class DemoPressureMonitor(
    private val scope: CoroutineScope,
    private val onPressure: (Double) -> Unit,
) {
    private var job: Job? = null
    private var currentPressure = 0.0
    private var shotStartTime: Long? = null
    private var shotDurationSeconds: Double = 30.0

    fun start() {
        if (job != null) return
        job = scope.launch {
            while (isActive) {
                tick()
                delay(100) // 10 Hz telemetry stream
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        stopSimulation()
    }

    fun tare() {
        currentPressure = 0.0
    }

    fun simulate(recipe: com.brewlog.app.domain.Recipe? = null, delaySeconds: Double = 0.0) {
        val duration = (recipe?.targetTime ?: 30.0).coerceIn(15.0, 60.0)
        simulateShot(durationSeconds = duration, delaySeconds = delaySeconds)
    }

    fun simulateShot(durationSeconds: Double = 30.0, delaySeconds: Double = 0.0) {
        shotDurationSeconds = durationSeconds
        shotStartTime = monotonicMillis() + (delaySeconds * 1000).toLong()
        currentPressure = 0.0
    }

    fun stopSimulation() {
        shotStartTime = null
        currentPressure = 0.0
    }

    private fun tick() {
        val start = shotStartTime
        if (start != null) {
            val now = monotonicMillis()
            if (now >= start) {
                val elapsed = (now - start) / 1000.0
            currentPressure = when {
                elapsed < 4.0 -> {
                    // Pre-infusion ramp up to 2.5 - 3.0 bar
                    (elapsed / 4.0) * 2.8
                }
                elapsed < 8.0 -> {
                    // Main ramp up to 9.0 bar
                    2.8 + ((elapsed - 4.0) / 4.0) * 6.2
                }
                elapsed < shotDurationSeconds -> {
                    // Gradual decline from 9.0 bar down to 6.5 bar (classic lever/profiling decline)
                    val progress = (elapsed - 8.0) / (shotDurationSeconds - 8.0)
                    9.0 - (progress * 2.5)
                }
                else -> {
                    // Shot ended: depressurize
                    0.0
                }
            }
            if (elapsed > shotDurationSeconds + 2.0) {
                stopSimulation()
            }
        } else {
            currentPressure = 0.0
        }
    } else {
        currentPressure = 0.0
    }

        val noise = Random.nextDouble(-0.03, 0.03)
        val finalBar = max(0.0, ((currentPressure + noise) * 100).roundToLong() / 100.0)
        onPressure(finalBar)
    }
}
