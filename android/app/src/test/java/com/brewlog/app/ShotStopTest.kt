package com.brewlog.app

import com.brewlog.app.machine.MachineStatus
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The app stops the shot at the yield in any phase of the profile, but never a flush or the grinder. */
class ShotStopTest {
    @Test
    fun testPullingShotCoversEveryPhase() {
        assertTrue(MachineStatus(processActive = true, processKind = "preinfusion", processLabel = "Compressing").isPullingShot)
        assertTrue(MachineStatus(processActive = true, processKind = "brew").isPullingShot)
        assertFalse(MachineStatus(processActive = true, processKind = "brew", processIsUtility = true).isPullingShot)
        assertFalse(MachineStatus(processActive = true, processKind = "grind").isPullingShot)
        assertFalse(MachineStatus(processActive = false, processKind = "brew").isPullingShot)
    }
}
