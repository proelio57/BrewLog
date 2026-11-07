package com.brewlog.app.analysis

import com.brewlog.app.domain.WeightSample
import kotlin.math.max
import kotlin.math.min

/**
 * Cleans up the scale's weight curve: single-reading spikes (a bump, a drop of water on the edge), the final
 * weight of a brew and the flow shown in the chart. 1:1 port of BrewLog/Analysis/WeightCleanup.swift.
 */
object WeightCleanup {
    /** Half the width of the median window in seconds: knocks that show for up to about 0.7 s disappear. */
    const val SPIKE_WINDOW = 0.75

    /**
     * Each reading replaced by the median of the readings within [SPIKE_WINDOW] seconds on either side (at least two
     * neighbours each side): a knock, a drop on the edge or lifting the cup for a moment disappears, even when the
     * scale sends several readings of it; a real step (a pour) stays.
     */
    fun despiked(samples: List<WeightSample>): List<WeightSample> {
        if (samples.size < 5) return samples
        var lo = 0
        var hi = 0
        return samples.indices.map { i ->
            val t = samples[i].t
            while (lo < i - 2 && samples[lo].t < t - SPIKE_WINDOW) lo++
            while (hi < samples.lastIndex && (hi < i + 2 || samples[hi + 1].t <= t + SPIKE_WINDOW)) hi++
            val window = samples.subList(lo, hi + 1).map { it.w }.sorted()
            WeightSample(t, window[window.size / 2])
        }
    }

    /**
     * The weight a brew ended with: the value the scale stayed on longest near the end, not the maximum or the last
     * reading. Only readings within 95 % of the (despiked) peak count, so lifting the dripper afterwards doesn't
     * either. Readings are grouped to 0.5 g; the result keeps 0.1 g. Null without a usable curve.
     */
    fun settledFinalWeight(samples: List<WeightSample>): Double? {
        val cleaned = despiked(samples)
        val peak = cleaned.maxOfOrNull { it.w } ?: return null
        if (peak <= 0) return null
        val threshold = peak * 0.95
        val time = HashMap<Double, Double>()
        val weighted = HashMap<Double, Double>()
        for (i in cleaned.indices) {
            if (cleaned[i].w < threshold) continue
            // How long the scale showed this reading: until the next one (capped, in case of a pause in the data).
            val duration = if (i + 1 < cleaned.size) (cleaned[i + 1].t - cleaned[i].t).coerceIn(0.0, 5.0) else 0.0
            val bucket = (cleaned[i].w * 2).roundHalfAwayFromZero() / 2
            time[bucket] = (time[bucket] ?: 0.0) + duration
            weighted[bucket] = (weighted[bucket] ?: 0.0) + cleaned[i].w * duration
        }
        val best = time.entries.maxWithOrNull(compareBy<Map.Entry<Double, Double>> { it.value }.thenBy { it.key })
        if (best == null || best.value <= 0) return (peak * 10).roundHalfAwayFromZero() / 10
        return ((weighted.getValue(best.key) / best.value) * 10).roundHalfAwayFromZero() / 10
    }

    /** Flow for the chart: from the despiked curve over a 2 s window, then averaged over five readings. */
    fun smoothedFlows(samples: List<WeightSample>): List<Double> {
        val flows = BrewAnalyzer.centeredFlows(despiked(samples), window = 2.0)
        if (flows.size < 5) return flows
        return flows.indices.map { i ->
            val window = flows.subList(max(i - 2, 0), min(i + 2, flows.lastIndex) + 1)
            window.sum() / window.size
        }
    }

    /** Like Swift's `rounded()`: halves away from zero (Kotlin's `round` rounds halves to even). */
    private fun Double.roundHalfAwayFromZero(): Double =
        if (this >= 0) (this + 0.5).let { kotlin.math.floor(it) } else -((-this + 0.5).let { kotlin.math.floor(it) })
}
