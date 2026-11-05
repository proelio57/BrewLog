package com.brewlog.app

import com.brewlog.app.brewing.ShotMonitor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Stopping and finishing an espresso shot, live numbers and GaggiMate's settings.
 * 1:1 port of BrewLogTests/ShotMonitorTests.swift.
 */
class ShotMonitorTest {

    @Test
    fun testStopsAheadOfTheYield() {
        assertTrue(ShotMonitor.shouldStop(weight = 34.2, flow = 2.0, yield = 36.0, lag = 1.0)) // 36.2 >= 36
        assertFalse(ShotMonitor.shouldStop(weight = 33.5, flow = 2.0, yield = 36.0, lag = 1.0)) // 35.5 < 36
    }

    @Test
    fun testStopsOnceAndIgnoresNegativeFlow() {
        val m = ShotMonitor(yield = 36.0, dose = 18.0, stopLag = 1.0, autoStop = true)
        assertEquals(ShotMonitor.Action.NONE, m.ingest(grams = 35.9, flow = -5.0, t = 20.0)) // bump: negative flow counts as 0
        assertEquals(ShotMonitor.Action.STOP, m.ingest(grams = 36.0, flow = 1.5, t = 20.1))
        assertEquals(ShotMonitor.Action.NONE, m.ingest(grams = 37.0, flow = 1.5, t = 20.2)) // only once
    }

    @Test
    fun testFinishesWhenSettledAfterNinetyPercent() {
        val m = ShotMonitor(yield = 36.0, dose = 18.0, stopLag = 1.0, autoStop = false)
        val actions = mutableListOf<ShotMonitor.Action>()
        for (i in 0 until 8) {
            val weight = 33.0 + if (i % 2 == 0) 0.1 else 0.0
            actions.add(m.ingest(grams = weight, flow = 0.0, t = 30.0 + i * 0.2))
        }
        // 33 g >= 32.4 (90 %), settled within +/- 0.3 g after 4 readings — and only once.
        assertEquals(1, actions.count { it == ShotMonitor.Action.FINISH })
        assertEquals(3, actions.indexOf(ShotMonitor.Action.FINISH))
    }

    @Test
    fun testNotFinishedBelowNinetyPercent() {
        val m = ShotMonitor(yield = 36.0, dose = 18.0, stopLag = 1.0, autoStop = false)
        for (i in 0 until 10) {
            assertEquals(ShotMonitor.Action.NONE, m.ingest(grams = 20.0, flow = 0.0, t = i * 0.2))
        }
    }

    @Test
    fun testFirstDropsAndLiveRatio() {
        val m = ShotMonitor(yield = 36.0, dose = 18.0, stopLag = 1.0, autoStop = true)
        m.ingest(grams = 0.4, flow = 0.2, t = 5.0)
        m.ingest(grams = 1.2, flow = 0.8, t = 6.5)
        assertEquals(6.5, m.firstDropsTime!!, 0.0001)
        assertEquals(1.2 / 18.0, m.liveRatio!!, 0.0001)
    }

    @Test
    fun testNoYieldNoStop() {
        val m = ShotMonitor(yield = 0.0, dose = 0.0, stopLag = 1.0, autoStop = true)
        assertEquals(ShotMonitor.Action.NONE, m.ingest(grams = 50.0, flow = 3.0, t = 10.0))
        assertNull(m.liveRatio)
    }

    @Test
    fun testGaggiMateWins() {
        assertEquals(91.0, ShotMonitor.shotTemperature(recipe = 93.0, machineTarget = 91.0, measuredAverage = 90.4), 0.0001)
        assertEquals(90.4, ShotMonitor.shotTemperature(recipe = 93.0, machineTarget = null, measuredAverage = 90.4), 0.0001)
        assertEquals(93.0, ShotMonitor.shotTemperature(recipe = 93.0, machineTarget = 0.0, measuredAverage = null), 0.0001) // implausible
        assertEquals(6.0, ShotMonitor.targetPressure(recipe = 9.0, machineTarget = 6.0)!!, 0.0001)
        assertEquals(9.0, ShotMonitor.targetPressure(recipe = 9.0, machineTarget = null)!!, 0.0001)
    }

    @Test
    fun testNoReadingsNoDecision() {
        assertFalse(ShotMonitor.isSettled(emptyList(), now = 10.0))
        assertFalse(
            ShotMonitor.isSettled(
                listOf(ShotMonitor.Reading(t = 9.9, grams = 30.0), ShotMonitor.Reading(t = 10.0, grams = 30.0)),
                now = 10.0,
            ),
        ) // < 4 readings
    }
}
