package com.brewlog.app

import com.brewlog.app.analysis.WeightCleanup
import com.brewlog.app.domain.WeightSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Cleaning up the scale's weight curve: spikes, the settled final weight and the smoothed flow.
 * 1:1 port of BrewLogTests/WeightCleanupTests.swift.
 */
class WeightCleanupTest {

    private fun samples(values: List<Double>, step: Double = 0.5, start: Double = 0.0): List<WeightSample> =
        values.mapIndexed { i, w -> WeightSample(start + i * step, w) }

    private fun repeat(value: Double, count: Int) = List(count) { value }

    @Test
    fun testSingleSpikeIsRemoved() {
        val raw = samples(listOf(100.0, 100.0, 160.0, 100.0, 100.0, 100.0))
        val cleaned = WeightCleanup.despiked(raw)
        assertEquals(List(6) { 100.0 }, cleaned.map { it.w })
        assertEquals(raw.map { it.t }, cleaned.map { it.t })
    }

    @Test
    fun testRealStepIsKept() {
        val cleaned = WeightCleanup.despiked(samples(listOf(100.0, 100.0, 100.0, 150.0, 150.0, 150.0, 150.0)))
        assertEquals(150.0, cleaned.last().w, 0.0)
        assertEquals(100.0, cleaned.first().w, 0.0)
    }

    @Test
    fun testFinalWeightIgnoresSpikesAtTheEnd() {
        val values = repeat(0.0, 4) + listOf(100.0, 180.0, 220.0) + repeat(230.0, 60) + listOf(236.0, 230.0, 230.0, 233.0)
        assertEquals(230.0, WeightCleanup.settledFinalWeight(samples(values))!!, 0.001)
    }

    @Test
    fun testFinalWeightTakesTheLongestPlateau() {
        val values = repeat(228.0, 10) + repeat(230.0, 40) + listOf(231.0)
        assertEquals(230.0, WeightCleanup.settledFinalWeight(samples(values))!!, 0.001)
    }

    @Test
    fun testFinalWeightIgnoresLiftingTheDripper() {
        val values = repeat(230.0, 40) + repeat(180.0, 120)
        assertEquals(230.0, WeightCleanup.settledFinalWeight(samples(values))!!, 0.001)
    }

    @Test
    fun testFinalWeightKeepsDecimals() {
        val values = repeat(36.4, 20) + listOf(36.6)
        assertEquals(36.4, WeightCleanup.settledFinalWeight(samples(values))!!, 0.001)
    }

    @Test
    fun testFinalWeightWithoutSamples() {
        assertNull(WeightCleanup.settledFinalWeight(emptyList()))
        assertNull(WeightCleanup.settledFinalWeight(samples(listOf(0.0, 0.0, 0.0))))
    }

    @Test
    fun testSmoothedFlowIsSteadyDespiteJitter() {
        val values = (0 until 100).map { i -> 4 * i * 0.2 + if (i % 2 == 0) 0.5 else -0.5 }.toMutableList()
        values[50] += 60.0
        val flows = WeightCleanup.smoothedFlows(samples(values, step = 0.2))
        assertEquals(100, flows.size)
        for (flow in flows.subList(15, 85)) assertEquals(4.0, flow, 0.6)
    }

    /** 10 readings a second; a knock sent as several readings (0.4 s to 326 g mid-pour, 0.5 s to 265 g at the end). */
    @Test
    fun testSpikeOverSeveralReadingsIsRemoved() {
        val values = (MutableList(116) { it * 2.0 } + repeat(230.0, 200)).toMutableList()
        for (i in 60 until 64) values[i] = 326.0
        for (i in 250 until 255) values[i] = 265.0
        val raw = samples(values, step = 0.1)
        val cleaned = WeightCleanup.despiked(raw)
        assertEquals(230.0, cleaned.maxOf { it.w }, 0.001)
        assertEquals(132.0, cleaned[62].w, 0.001)
        assertEquals(230.0, WeightCleanup.settledFinalWeight(raw)!!, 0.001)
    }

    @Test
    fun testFastPourAt10HzIsKept() {
        val values = repeat(100.0, 30) + List(20) { 100.0 + it * 5 } + repeat(200.0, 30)
        assertEquals(values, WeightCleanup.despiked(samples(values, step = 0.1)).map { it.w })
    }
}
