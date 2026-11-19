package com.brewlog.app

import com.brewlog.app.brewing.ShotMonitor
import com.brewlog.app.domain.StopLagLearner
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Same cases as StopLagLearnerTests.swift. */
class StopLagLearnerTest {
    @Test fun measuredLagIsWhatArrivedAfterTheStopOverTheFlow() {
        assertEquals(1.8, StopLagLearner.measuredLag(33.0, 2.0, 36.6)!!, 0.001)
    }

    @Test fun shotsThatCantTeachAreSkipped() {
        assertNull(StopLagLearner.measuredLag(33.0, 0.2, 36.0))
        assertNull(StopLagLearner.measuredLag(33.0, 2.0, 20.0))
        assertNull(StopLagLearner.measuredLag(33.0, 2.0, 60.0))
    }

    @Test fun theLagStaysInRange() {
        assertEquals(0.3, StopLagLearner.measuredLag(33.0, 2.0, 33.0)!!, 0.0)
        assertEquals(3.0, StopLagLearner.updated(2.9, 5.0), 0.0)
    }

    @Test fun eachShotMovesHalfwayAndCounts() {
        val first = StopLagLearner.next(null, 1.0, 33.0, 2.0, 36.6)!!
        assertEquals(1.4, first.lag, 0.001)
        val second = StopLagLearner.next(first, 1.0, 33.0, 2.0, 36.6)!!
        assertEquals(1.6, second.lag, 0.001)
        assertEquals(2, second.shots)
        val key = StopLagLearner.key("gaggimate", false)
        val decoded = StopLagLearner.decode(StopLagLearner.encode(mapOf(key to second)))
        assertEquals(second, decoded[key])
        assertEquals(emptyMap<String, StopLagLearner.Learned>(), StopLagLearner.decode("not json"))
    }

    @Test fun theMonitorRemembersWeightAndFlowAtTheStop() {
        val monitor = ShotMonitor(yield = 36.0, dose = 18.0, stopLag = 1.0, autoStop = true)
        assertEquals(ShotMonitor.Action.NONE, monitor.ingest(30.0, 2.0, 20.0))
        assertEquals(ShotMonitor.Action.STOP, monitor.ingest(34.2, 2.0, 22.0))
        assertEquals(34.2, monitor.weightAtStop!!, 0.0)
        assertEquals(2.0, monitor.flowAtStop!!, 0.0)
    }
}
