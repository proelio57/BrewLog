package com.brewlog.app

import com.brewlog.app.brewing.BrewCue
import com.brewlog.app.brewing.BrewSession
import com.brewlog.app.domain.AppSettings
import com.brewlog.app.domain.BrewMethod
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.RecipeFilter
import com.brewlog.app.domain.RecipeLibrary
import com.brewlog.app.domain.RecipeStep
import com.brewlog.app.domain.StepAnnouncement
import com.brewlog.app.domain.StepKind
import com.brewlog.app.domain.ValveState
import com.brewlog.app.domain.valveChange
import com.brewlog.app.scale.ScaleCommands
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Same scenarios as testStepAnnouncements / testRecipeFilterByBrewer / testValveChanges in ToolsTests.swift. */
class VoiceValveFilterTest {
    private val presets by lazy { RecipeLibrary.parse(File("../../Shared/recipes.json").readText()) }

    private fun recipe(id: String, method: BrewMethod, steps: List<RecipeStep> = listOf(RecipeStep(StepKind.BLOOM, 0.0, 45.0))) =
        Recipe(id = id, name = id, method = method, steps = steps)

    @Test fun stepAnnouncements() {
        assertEquals("Bloom to 45 grams.", StepAnnouncement.text(RecipeStep(StepKind.BLOOM, 0.0, 45.0)))
        assertEquals("Pour to 150 grams. Slow spiral.", StepAnnouncement.text(RecipeStep(StepKind.POUR, 45.0, 150.4, note = "Slow spiral")))
        assertEquals("Swirl gently.", StepAnnouncement.text(RecipeStep(StepKind.SWIRL, 90.0)))
        assertEquals("Open the valve.", StepAnnouncement.text(RecipeStep(StepKind.OPEN_VALVE, 120.0)))
        assertEquals("Next, pour to 250 grams.", StepAnnouncement.preview(RecipeStep(StepKind.POUR, 75.0, 250.0, note = "Long note is not read ahead")))
        assertEquals("Stir.", StepAnnouncement.text(RecipeStep(StepKind.STIR, 10.0, note = "word ".repeat(30))))
        assertEquals("1 gram", StepAnnouncement.grams(1.0))
    }

    @Test fun recipeFilterByBrewer() {
        val v60 = recipe("a", BrewMethod.V60)
        val any = recipe("b", BrewMethod.UNIVERSAL)
        val shot = recipe("c", BrewMethod.ESPRESSO)
        val sw = recipe("d", BrewMethod.HYBRID)
        assertTrue(RecipeFilter.matches(v60, null))
        assertTrue("any pour-over fits a V60", RecipeFilter.matches(any, BrewMethod.V60))
        assertFalse(RecipeFilter.matches(any, BrewMethod.ESPRESSO))
        assertFalse(RecipeFilter.matches(sw, BrewMethod.V60))

        val sections = RecipeFilter.sections(listOf(recipe("mine", BrewMethod.HYBRID)), listOf(v60, any, shot, sw), BrewMethod.HYBRID)
        assertEquals(listOf("My recipes", "Hario Switch", "Any pour-over"), sections.map { it.title })
        assertEquals(4, RecipeFilter.sections(emptyList(), listOf(v60, any, shot, sw), null).size)
        assertEquals(listOf(BrewMethod.V60, BrewMethod.ESPRESSO), RecipeFilter.methods(listOf(v60, any, shot)))
    }

    @Test fun valveChanges() {
        val switchRecipe = recipe("s", BrewMethod.HYBRID, listOf(
            RecipeStep(StepKind.BLOOM, 0.0, 60.0, ValveState.OPEN),
            RecipeStep(StepKind.POUR, 30.0, 120.0, ValveState.OPEN),
            RecipeStep(StepKind.POUR, 75.0, 280.0, ValveState.CLOSED),
            RecipeStep(StepKind.SWIRL, 90.0),
            RecipeStep(StepKind.OPEN_VALVE, 105.0),
        ))
        assertNull("the starting position isn't a change", switchRecipe.valveChange(0))
        assertNull(switchRecipe.valveChange(1))
        assertEquals(ValveState.CLOSED, switchRecipe.valveChange(2))
        assertNull(switchRecipe.valveChange(3))
        assertEquals(ValveState.OPEN, switchRecipe.valveChange(4))
        assertNull(switchRecipe.valveChange(9))
        assertNull(recipe("v", BrewMethod.V60).valveChange(1))
        for (preset in presets.filter { it.method == BrewMethod.HYBRID }) {
            assertTrue(preset.id, preset.steps.indices.any { preset.valveChange(it) != null })
        }
    }

    private class FakeScale : ScaleCommands {
        override val isReady = false
        override fun tare() {}
        override fun prepareForBrew(recipe: Recipe) {}
        override fun prepareForDosing(dose: Double) {}
        override fun dosingFinished() {}
        override fun brewStarted() {}
        override fun brewFinished() {}
    }

    /** Runs a brew without a scale from 0 to [until] seconds in 50 ms ticks. */
    private fun run(recipe: Recipe, settings: AppSettings, until: Double): Pair<List<Pair<Long, BrewCue>>, List<String>> {
        var now = 0L
        val cues = mutableListOf<Pair<Long, BrewCue>>()
        val spoken = mutableListOf<String>()
        val session = BrewSession(recipe, FakeScale(), { settings }, { cues += now to it }, clock = { now }, onSpeak = { spoken += it })
        session.ready()
        session.startManually()
        while (now < until * 1000) {
            now += 50
            session.tick()
        }
        return cues to spoken
    }

    @Test fun valveTicksOnlyBeforeValveChanges() {
        val switchRecipe = recipe("s", BrewMethod.HYBRID, listOf(
            RecipeStep(StepKind.BLOOM, 0.0, 60.0, ValveState.CLOSED),
            RecipeStep(StepKind.POUR, 30.0, 120.0, ValveState.CLOSED),
            RecipeStep(StepKind.OPEN_VALVE, 60.0),
        ))
        val (cues, _) = run(switchRecipe, AppSettings(countdownTicks = false, valveCountdown = true), 62.0)
        val ticks = cues.filter { it.second == BrewCue.TICK }.map { it.first }
        // 3-2-1 before 1:00 (valve opens), nothing before 0:30 (valve stays closed).
        assertEquals(3, ticks.size)
        assertTrue(ticks.all { it in 57_000L..60_000L })
        val (quiet, _) = run(switchRecipe, AppSettings(countdownTicks = false, valveCountdown = false), 62.0)
        assertTrue(quiet.none { it.second == BrewCue.TICK })
    }

    @Test fun voicePromptsFollowTheSteps() {
        val steps = listOf(
            RecipeStep(StepKind.BLOOM, 0.0, 45.0),
            RecipeStep(StepKind.POUR, 45.0, 150.0),
            RecipeStep(StepKind.POUR, 75.0, 250.0),
        )
        val (_, spoken) = run(recipe("v", BrewMethod.V60, steps), AppSettings(voicePrompts = true), 80.0)
        assertEquals(
            listOf("Bloom to 45 grams.", "Next, pour to 150 grams.", "Pour to 150 grams.", "Next, pour to 250 grams.", "Pour to 250 grams."),
            spoken,
        )
        val (_, silent) = run(recipe("v", BrewMethod.V60, steps), AppSettings(voicePrompts = false), 80.0)
        assertTrue(silent.isEmpty())
    }
}
