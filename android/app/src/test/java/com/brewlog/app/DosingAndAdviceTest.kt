package com.brewlog.app

import com.brewlog.app.analysis.AnalysisInput
import com.brewlog.app.analysis.BrewAnalyzer
import com.brewlog.app.brewing.BeanDosing
import com.brewlog.app.brewing.BrewCue
import com.brewlog.app.brewing.BrewPhase
import com.brewlog.app.brewing.BrewSession
import com.brewlog.app.domain.AppSettings
import com.brewlog.app.domain.BrewMethod
import com.brewlog.app.domain.FilterFlow
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.RecipeFilter
import com.brewlog.app.domain.RecipeLibrary
import com.brewlog.app.domain.RoastLevel
import com.brewlog.app.domain.TasteFeedback
import com.brewlog.app.scale.ScaleCommands
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Same scenarios as DosingAndAdviceTests.swift and web/tests/dosing.test.ts. */
class DosingAndAdviceTest {
    private val presets by lazy { RecipeLibrary.parse(File("../../Shared/recipes.json").readText()) }
    private fun preset(id: String) = presets.first { it.id == id }

    // MARK: Weighing the beans

    @Test fun doseStatus() {
        assertEquals(BeanDosing.Status.EMPTY, BeanDosing.status(0.2, 15.0))
        assertEquals(BeanDosing.Status.UNDER, BeanDosing.status(12.0, 15.0))
        assertEquals(BeanDosing.Status.ON_TARGET, BeanDosing.status(14.8, 15.0))
        assertEquals(BeanDosing.Status.ON_TARGET, BeanDosing.status(15.2, 15.0))
        assertEquals(BeanDosing.Status.OVER, BeanDosing.status(15.5, 15.0))
        assertEquals(BeanDosing.Status.EMPTY, BeanDosing.status(Double.NaN, 15.0))
    }

    @Test fun doseProgressIsClamped() {
        assertEquals(0.5, BeanDosing.progress(7.5, 15.0), 0.001)
        assertEquals(1.0, BeanDosing.progress(20.0, 15.0), 0.0)
        assertEquals(0.0, BeanDosing.progress(-2.0, 15.0), 0.0)
        assertEquals(0.0, BeanDosing.progress(5.0, 0.0), 0.0)
    }

    @Test fun acceptedDoseUsesTheReadingOrFallsBack() {
        assertEquals(15.3, BeanDosing.acceptedDose(15.26, 15.0), 0.0001)
        assertEquals(15.0, BeanDosing.acceptedDose(0.1, 15.0), 0.0)
        assertEquals(15.0, BeanDosing.acceptedDose(900.0, 15.0), 0.0)
        assertEquals(15.0, BeanDosing.acceptedDose(Double.POSITIVE_INFINITY, 15.0), 0.0)
    }

    private class FakeScale(override var isReady: Boolean = true) : ScaleCommands {
        val commands = mutableListOf<String>()
        override fun tare() { commands += "tare" }
        override fun prepareForBrew(recipe: Recipe) { commands += "prepare" }
        override fun prepareForDosing(dose: Double) { commands += "dose" }
        override fun dosingFinished() { commands += "doseDone" }
        override fun brewStarted() { commands += "start" }
        override fun brewFinished() { commands += "stop" }
    }

    @Test fun startsByWeighingPingsOnceAndSavesTheWeighedDose() {
        val recipe = preset("everyday-3-pour")
        val scale = FakeScale()
        val cues = mutableListOf<BrewCue>()
        var now = 0L
        val session = BrewSession(recipe, scale, { AppSettings() }, { cues += it }, clock = { now })
        session.prepare()
        session.prepare()
        assertEquals(BrewPhase.DOSING, session.phase)
        assertEquals(listOf("dose"), scale.commands)
        var grams = 0.0
        while (grams <= recipe.dose + 0.1) {
            now += 100
            session.ingest(grams, now)
            grams += 0.5
        }
        session.ingest(recipe.dose + 0.1, now + 100)
        assertEquals(listOf(BrewCue.TARGET), cues)
        session.acceptDose()
        assertEquals(BrewPhase.PREPARING, session.phase)
        assertEquals(recipe.dose + 0.1, session.dose, 0.0001)
        assertEquals(recipe.dose + 0.1, session.state.value.weighedDose!!, 0.0001)
        // Opening the screen again doesn't start weighing again.
        session.prepare()
        assertEquals(BrewPhase.PREPARING, session.phase)
        session.ready()
        assertEquals(listOf("dose", "doseDone", "prepare"), scale.commands)
    }

    @Test fun skipsWeighingWhenSwitchedOffOrWithoutScale() {
        val off = BrewSession(preset("everyday-3-pour"), FakeScale(), { AppSettings(weighBeansFirst = false) }, {})
        off.prepare()
        assertEquals(BrewPhase.PREPARING, off.phase)
        val noScale = BrewSession(preset("everyday-3-pour"), FakeScale(isReady = false), { AppSettings() }, {})
        noScale.prepare()
        assertEquals(BrewPhase.PREPARING, noScale.phase)
        assertEquals(preset("everyday-3-pour").dose, noScale.dose, 0.0)
    }

    // MARK: Recipe advice

    @Test fun clearerAlternativeIsNeverTheBrewedRecipe() {
        for (recipe in presets.filter { it.method != BrewMethod.ESPRESSO }) {
            val alternative = RecipeFilter.clearerAlternative(recipe, presets) ?: continue
            assertNotEquals(recipe.id, alternative.id)
            assertNotEquals(recipe.name, alternative.name)
            assertFalse(alternative.id.startsWith("template-"))
            assertTrue(RecipeFilter.matches(alternative, if (recipe.method == BrewMethod.UNIVERSAL) null else recipe.method))
        }
    }

    @Test fun raoPointsToAnotherClearRecipeAndSwitchStaysOnSwitch() {
        val rao = preset("rao-v60")
        val fromRao = RecipeFilter.clearerAlternative(rao, presets)
        assertNotNull(fromRao)
        assertNotEquals(rao.id, fromRao!!.id)
        assertTrue(fromRao.taste.clarity >= rao.taste.clarity)
        val immersion = preset("switch-immersion")
        val fromSwitch = RecipeFilter.clearerAlternative(immersion, presets)!!
        assertTrue(RecipeFilter.matches(fromSwitch, BrewMethod.HYBRID))
        assertTrue(fromSwitch.taste.clarity > immersion.taste.clarity)
    }

    @Test fun copyOfTheSameRecipeIsNotSuggested() {
        assertNull(RecipeFilter.clearerAlternative(preset("rao-v60").copy(id = "custom-rao"), listOf(preset("rao-v60"))))
    }

    private fun flatInput(recipe: Recipe, flow: FilterFlow?, alternatives: List<Recipe> = emptyList()) = AnalysisInput(
        recipe = recipe, samples = emptyList(), usedScale = false, totalTime = recipe.targetTime, finalWeight = recipe.water,
        dose = recipe.dose, waterTemp = recipe.temperature, roastLevel = RoastLevel.LIGHT, daysOffRoast = 14,
        filterName = "Paper", filterFlow = flow, filterIdealRoast = null, grinder = null,
        feedback = setOf(TasteFeedback.FLAT), history = emptyList(), alternatives = alternatives,
    )

    @Test fun flatCupNeverNamesTheBrewedRecipe() {
        val rao = preset("rao-v60")
        val clarity = BrewAnalyzer.analyze(flatInput(rao, FilterFlow.FAST, presets)).suggestions.first { it.key == "clarity" }
        assertFalse(clarity.title.contains(rao.name))
        assertTrue(clarity.detail, clarity.detail.endsWith("than ${rao.name}."))
        assertFalse(clarity.detail.contains("CAFEC"))
    }

    @Test fun withoutAlternativesOnlyThePaperIsSuggested() {
        assertEquals("Try a faster paper", BrewAnalyzer.clarityAdvice(preset("rao-v60"), flatInput(preset("rao-v60"), FilterFlow.SLOW))?.first)
        assertNull(BrewAnalyzer.clarityAdvice(preset("rao-v60"), flatInput(preset("rao-v60"), FilterFlow.FAST)))
    }
}
