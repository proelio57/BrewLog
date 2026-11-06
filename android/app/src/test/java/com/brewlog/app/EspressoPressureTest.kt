package com.brewlog.app

import com.brewlog.app.brewing.BrewPhase
import com.brewlog.app.brewing.BrewSession
import com.brewlog.app.domain.AppSettings
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.RecipeLibrary
import com.brewlog.app.machine.MachineCapability
import com.brewlog.app.machine.MachineConnection
import com.brewlog.app.machine.MachineKind
import com.brewlog.app.machine.MachineState
import com.brewlog.app.machine.MachineStatus
import com.brewlog.app.scale.ScaleCommands
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Espresso with the BOOKOO Espresso Monitor (no machine connection): pressure starts the shot and makes the curve. */
class EspressoPressureTest {
    private val presets by lazy { RecipeLibrary.parse(File("../../Shared/recipes.json").readText()) }

    private class FakeScale : ScaleCommands {
        val commands = mutableListOf<String>()
        override val isReady = true
        override fun tare() { commands += "tare" }
        override fun prepareForBrew(recipe: Recipe) { commands += "prepare" }
        override fun prepareForDosing(dose: Double) { commands += "dose" }
        override fun dosingFinished() { commands += "doseDone" }
        override fun brewStarted() { commands += "start" }
        override fun brewFinished() { commands += "stop" }
    }

    @Test fun pressureStartsTheShotAndIsRecorded() {
        val recipe = presets.first { it.id == "espresso-classic" }
        var now = 0L
        val prepared = mutableListOf<String>()
        val session = BrewSession(
            recipe, FakeScale(), { AppSettings(weighBeansFirst = false) }, {}, clock = { now },
            monitorReady = { true }, prepareMonitor = { prepared += it.id },
        )
        assertTrue(session.isEspresso)
        assertTrue(session.hasPressure)
        session.ready()
        assertEquals(listOf("espresso-classic"), prepared)
        // Below 1 bar nothing happens.
        now = 500
        session.monitorReading(0.4, now)
        assertEquals(BrewPhase.ARMED, session.phase)
        // The pump builds pressure: the shot timer starts.
        now = 1_000
        session.monitorReading(1.2, now)
        assertEquals(BrewPhase.BREWING, session.phase)
        var bar = 1.2
        repeat(50) { step ->
            now = 1_000L + (step + 1) * 100L
            bar = minOf(9.0, bar + 0.5)
            session.monitorReading(bar, now)
            session.tick()
        }
        val curve = session.recordedMachineSamples()
        // Throttled to one sample every 0.2 s.
        assertTrue("got ${curve.size} samples", curve.size in 15..27)
        assertEquals(9.0, curve.last().p, 0.001)
        assertTrue(curve.zipWithNext().all { (a, b) -> b.t > a.t })
        session.finish()
        assertEquals(BrewPhase.FINISHED, session.phase)
    }

    @Test fun pourOverIgnoresThePressureSensor() {
        val recipe = presets.first { it.id == "everyday-3-pour" }
        val session = BrewSession(recipe, FakeScale(), { AppSettings(weighBeansFirst = false) }, {}, clock = { 0L }, monitorReady = { true })
        session.ready()
        session.monitorReading(5.0, 100)
        assertEquals(BrewPhase.ARMED, session.phase)
        assertTrue(session.recordedMachineSamples().isEmpty())
    }

    @Test fun testMachineKindSuggestedFromBrewerName() {
        assertEquals(MachineKind.GAGGIMATE, MachineKind.suggested("Gaggia Classic (GaggiMate)"))
        assertEquals(MachineKind.DECENT, MachineKind.suggested("Decent DE1"))
        assertEquals(MachineKind.LA_MARZOCCO, MachineKind.suggested("La Marzocco Linea Micra"))
        assertEquals(MachineKind.LA_MARZOCCO, MachineKind.suggested("la marzocco linea mini"))
        assertNull("a plain Gaggia has no app connection", MachineKind.suggested("Gaggia Classic"))
        assertNull(MachineKind.suggested("Rancilio Silvia"))
        assertNull(MachineKind.suggested("Hario V60 02"))
    }

    @Test fun testMachineCapabilitiesAndControl() {
        assertEquals(
            setOf(
                MachineCapability.PROFILES,
                MachineCapability.TEMPERATURE_NUDGE,
                MachineCapability.MACHINE_SCALE,
                MachineCapability.START_STOP,
            ),
            MachineKind.GAGGIMATE.capabilities,
        )
        assertEquals(
            setOf(
                MachineCapability.PROFILES,
                MachineCapability.TEMPERATURE_NUDGE,
                MachineCapability.MACHINE_SCALE,
                MachineCapability.START_STOP,
            ),
            MachineKind.DEMO.capabilities,
        )
        assertEquals(setOf(MachineCapability.START_STOP), MachineKind.DECENT.capabilities)
        assertEquals(
            setOf(MachineCapability.POWER, MachineCapability.TEMPERATURE_NUDGE),
            MachineKind.LA_MARZOCCO.capabilities,
        )
        assertEquals(emptySet<MachineCapability>(), MachineKind.NONE.capabilities)

        val connectedGaggi = MachineState(kind = MachineKind.GAGGIMATE, connection = MachineConnection.CONNECTED)
        assertTrue(connectedGaggi.canControl)
        assertTrue(connectedGaggi.readsPressure)

        val disconnectedGaggi = MachineState(kind = MachineKind.GAGGIMATE, connection = MachineConnection.OFF)
        assertFalse(disconnectedGaggi.canControl)
        assertTrue(disconnectedGaggi.readsPressure)

        val lmConnected = MachineState(kind = MachineKind.LA_MARZOCCO, connection = MachineConnection.CONNECTED)
        assertFalse(lmConnected.canControl)
        assertFalse(lmConnected.readsPressure)

        val noMachine = MachineState(kind = MachineKind.NONE, connection = MachineConnection.OFF)
        assertFalse(noMachine.canControl)
        assertFalse(noMachine.readsPressure)

        val gaggiNoPressure = MachineState(
            kind = MachineKind.GAGGIMATE,
            connection = MachineConnection.CONNECTED,
            status = MachineStatus(hasPressure = false),
        )
        assertFalse(gaggiNoPressure.readsPressure)
    }
}
