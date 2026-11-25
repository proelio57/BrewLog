package com.brewlog.app

import com.brewlog.app.domain.BrewMistake
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BrewMistakeTest {
    @Test fun anEmptyShotIsAMistake() =
        assertEquals(BrewMistake.TOO_SHORT, BrewMistake.check(true, true, 0.0, 0.0, 36.0))

    @Test fun aVeryShortShotIsAMistake() =
        assertEquals(BrewMistake.TOO_SHORT, BrewMistake.check(true, false, 5.0, 0.0, 36.0))

    @Test fun hardlyAnyWeightIsAMistake() =
        assertEquals(BrewMistake.TOO_LITTLE, BrewMistake.check(true, true, 25.0, 3.0, 36.0))

    @Test fun aRealShotIsFine() = assertNull(BrewMistake.check(true, true, 28.0, 36.0, 36.0))

    @Test fun withoutAScaleTheWeightDoesNotCount() = assertNull(BrewMistake.check(true, false, 28.0, 0.0, 36.0))

    @Test fun pourOversNeedMoreTime() {
        assertEquals(BrewMistake.TOO_SHORT, BrewMistake.check(false, true, 20.0, 240.0, 240.0))
        assertNull(BrewMistake.check(false, true, 180.0, 240.0, 240.0))
    }
}
