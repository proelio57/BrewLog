package com.brewlog.app

import com.brewlog.app.analysis.PressureFocus
import com.brewlog.app.analysis.PressureFocusMode
import com.brewlog.app.analysis.PressureZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** 1:1 with BrewLogTests/PressureFocusTests.swift. */
class PressureFocusTest {
    @Test
    fun testModes() {
        assertTrue(PressureFocus.isActive(PressureFocusMode.AUTOMATIC, sensorIsSource = true, hasPressure = true))
        assertFalse(PressureFocus.isActive(PressureFocusMode.AUTOMATIC, sensorIsSource = false, hasPressure = true))
        assertTrue(PressureFocus.isActive(PressureFocusMode.ALWAYS, sensorIsSource = false, hasPressure = true))
        assertFalse(PressureFocus.isActive(PressureFocusMode.ALWAYS, sensorIsSource = false, hasPressure = false))
        assertFalse(PressureFocus.isActive(PressureFocusMode.OFF, sensorIsSource = true, hasPressure = true))
    }

    @Test
    fun testZones() {
        assertEquals(PressureZone.LOW, PressureFocus.zone(7.9, 9.0))
        assertEquals(PressureZone.ON_TARGET, PressureFocus.zone(9.2, 9.0))
        assertEquals(PressureZone.HIGH, PressureFocus.zone(10.1, 9.0))
        assertEquals(PressureZone.ON_TARGET, PressureFocus.zone(8.5, 9.0))
        assertEquals(PressureZone.ON_TARGET, PressureFocus.zone(9.5, 9.0))
        assertEquals(PressureZone.NO_TARGET, PressureFocus.zone(9.0, null))
        assertEquals(PressureZone.NO_TARGET, PressureFocus.zone(null, 9.0))
        assertEquals(PressureZone.NO_TARGET, PressureFocus.zone(Double.NaN, 9.0))
    }
}
