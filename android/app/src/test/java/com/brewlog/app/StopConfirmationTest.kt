package com.brewlog.app

import com.brewlog.app.domain.StopConfirmation
import com.brewlog.app.domain.StopConfirmation.Result
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StopConfirmationTest {
    @Test fun theFirstTapOnlyArms() {
        val stop = StopConfirmation()
        assertEquals(Result.ARM, stop.tap(0))
        assertTrue(stop.isArmed(1000))
    }

    @Test fun aDoubleTapDoesNotStop() {
        val stop = StopConfirmation()
        stop.tap(0)
        assertEquals(Result.IGNORE, stop.tap(200))
        assertTrue(stop.isArmed(300))
    }

    @Test fun aSecondDeliberateTapStops() {
        val stop = StopConfirmation()
        stop.tap(0)
        assertEquals(Result.STOP, stop.tap(1500))
        assertFalse(stop.isArmed(1600))
    }

    @Test fun theArmedStateRunsOut() {
        val stop = StopConfirmation()
        stop.tap(0)
        assertFalse(stop.isArmed(StopConfirmation.TIMEOUT_MS + 100))
        assertEquals(Result.ARM, stop.tap(StopConfirmation.TIMEOUT_MS + 100))
    }
}
