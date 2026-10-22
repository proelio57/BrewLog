package com.brewlog.app

import com.brewlog.app.analysis.AnalysisInput
import com.brewlog.app.analysis.BrewAnalyzer
import com.brewlog.app.analysis.ExtractionLean
import com.brewlog.app.analysis.GrindRecommender
import com.brewlog.app.analysis.GrinderContext
import com.brewlog.app.analysis.PastBrew
import com.brewlog.app.brewing.BrewCue
import com.brewlog.app.brewing.BrewPhase
import com.brewlog.app.brewing.BrewSession
import com.brewlog.app.domain.AppSettings
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.Equipment
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.domain.FilterFlow
import com.brewlog.app.domain.GrindUnit
import com.brewlog.app.domain.GrinderSpec
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.RecipeLibrary
import com.brewlog.app.domain.RoastLevel
import com.brewlog.app.domain.TasteFeedback
import com.brewlog.app.domain.WeightSample
import com.brewlog.app.scale.ScaleCommands
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.min

/** Same scenarios and numbers as BrewAnalyzerTests.swift, so both platforms are guaranteed to agree. */
class BrewAnalyzerTest {
    private val presets by lazy { RecipeLibrary.parse(File("../../Shared/recipes.json").readText()) }
    private val comandante = GrinderSpec(GrindUnit.CLICKS, 1.0, 2.0, true)
    private fun kasuya() = presets.first { it.id == "kasuya-46" }
    private fun fastCase() = kasuya().copy(targetTime = 230.0)

    /** Each pour starts at its scheduled time (+ delay) and rises at [rate] g/s up to its target (+ overshoot). 10 Hz. */
    private fun simulate(recipe: Recipe, rate: Double = 6.0, delays: List<Double> = emptyList(),
                         overshoot: List<Double> = emptyList(), until: Double): List<WeightSample> {
        val pours = recipe.pourSteps
        val samples = mutableListOf<WeightSample>()
        var weight = 0.0
        var i = 0
        while (true) {
            val t = i / 10.0
            if (t > until + 0.0001) break
            val index = pours.indices.lastOrNull { pours[it].time + (delays.getOrNull(it) ?: 0.0) <= t }
            if (index != null) {
                val goal = (pours[index].target ?: 0.0) + (overshoot.getOrNull(index) ?: 0.0)
                if (weight < goal) weight = min(goal, weight + rate * 0.1)
            }
            samples.add(WeightSample(t, weight))
            i++
        }
        return samples
    }

    private fun input(recipe: Recipe, samples: List<WeightSample>, totalTime: Double, finalWeight: Double? = null,
                      temp: Double? = null, roast: RoastLevel? = RoastLevel.LIGHT, days: Int? = 14,
                      grinder: GrinderContext? = null, feedback: Set<TasteFeedback> = emptySet(),
                      history: List<PastBrew> = emptyList(), filterIdealRoast: RoastLevel? = null, usedScale: Boolean = true) =
        AnalysisInput(recipe, samples, usedScale, totalTime, finalWeight ?: (samples.maxOfOrNull { it.w } ?: 0.0), recipe.dose,
            temp ?: recipe.temperature, roast, days, "Test paper", FilterFlow.MEDIUM, filterIdealRoast, grinder, feedback, history)

    @Test fun detectsEveryPourOfFourSix() {
        val recipe = kasuya()
        val segments = BrewAnalyzer.detectSegments(simulate(recipe, until = 210.0))
        assertEquals(5, segments.size)
        segments.zip(recipe.pourSteps).forEach { (segment, step) ->
            assertEquals(step.time, segment.start, 0.3)
            assertEquals(step.target!!, segment.endWeight, 0.5)
        }
        val pours = BrewAnalyzer.matchPours(recipe, segments)
        assertTrue(pours.all { it.detected })
        assertEquals(listOf(0, 1, 2, 3, 4), pours.map { it.number })
        assertEquals(6.0, pours[2].averageFlow!!, 0.5)
    }

    @Test fun flagsLateStartAndOverpour() {
        val recipe = kasuya()
        val samples = simulate(recipe, delays = listOf(0.0, 9.0, 0.0, 0.0, 0.0), overshoot = listOf(0.0, 12.0, 12.0, 12.0, 12.0), until = 215.0)
        val analysis = BrewAnalyzer.analyze(input(recipe, samples, 215.0, finalWeight = 312.0))
        assertEquals(9.0, analysis.pours[1].startDelta!!, 0.5)
        assertTrue(analysis.findings.any { it.title.contains("Pour 1 started 9 s late") })
        assertTrue(analysis.findings.any { it.title.contains("overpoured by 12 g") })
    }

    @Test fun splitsContinuousPourAtIntermediateTarget() {
        val recipe = presets.first { it.id == "hoffmann-ultimate-v60" }
        val samples = (0..2100).map { i ->
            val t = i / 10.0
            WeightSample(t, when {
                t < 10 -> t * 6
                t < 45 -> 60.0
                else -> min(60 + (t - 45) * 8, 500.0)
            })
        }
        val analysis = BrewAnalyzer.analyze(input(recipe, samples, 210.0))
        assertEquals(3, analysis.pours.size)
        assertTrue(analysis.pours.all { it.detected })
        assertEquals(300.0, analysis.pours[1].reached!!, 9.0)
        assertEquals(75.0, analysis.pours[2].actualStart!!, 1.5)
    }

    @Test fun onPlanBrewIsBalanced() {
        val analysis = BrewAnalyzer.analyze(input(kasuya(), simulate(kasuya(), until = 210.0), 210.0))
        assertEquals(ExtractionLean.BALANCED, analysis.lean)
        assertFalse(analysis.findings.any { it.level == com.brewlog.app.analysis.FindingLevel.WARNING })
    }

    @Test fun sourAndFastSuggestsConcreteFinerGrind() {
        val recipe = fastCase()
        val analysis = BrewAnalyzer.analyze(input(recipe, simulate(recipe, until = 205.0), 205.0,
            grinder = GrinderContext("Comandante C40", comandante, 24.0), feedback = setOf(TasteFeedback.SOUR)))
        val top = analysis.suggestions.first()
        assertEquals("grind", top.key)
        assertEquals(22.0, top.grindTarget!!, 0.0)
        assertTrue(top.title.contains("22 clicks"))
        assertTrue(top.evidence.isNotEmpty())
        assertEquals(22.0, analysis.suggestedGrind!!, 0.0)
        assertEquals(ExtractionLean.UNDER, analysis.lean)
    }

    @Test fun veryFastBrewSuggestsBiggerStep() {
        val recipe = kasuya().copy(targetTime = 270.0)
        val analysis = BrewAnalyzer.analyze(input(recipe, simulate(recipe, until = 200.0), 200.0,
            grinder = GrinderContext("Comandante C40", comandante, 24.0), feedback = setOf(TasteFeedback.SOUR)))
        assertEquals(20.0, analysis.suggestedGrind!!, 0.0)
    }

    @Test fun bitterAndSlowSuggestsCoarser() {
        val analysis = BrewAnalyzer.analyze(input(kasuya(), simulate(kasuya(), until = 240.0), 240.0,
            grinder = GrinderContext("Comandante C40", comandante, 24.0), feedback = setOf(TasteFeedback.BITTER)))
        assertEquals("grind", analysis.suggestions.first().key)
        assertEquals(26.0, analysis.suggestedGrind!!, 0.0)
        assertEquals(ExtractionLean.OVER, analysis.lean)
    }

    @Test fun historyBracketsTheGrind() {
        val recipe = fastCase()
        val history = listOf(PastBrew(0, recipe.id, 18.0, 2, setOf(TasteFeedback.BITTER), 240.0))
        val analysis = BrewAnalyzer.analyze(input(recipe, simulate(recipe, until = 205.0), 205.0,
            grinder = GrinderContext("Comandante C40", comandante, 24.0), feedback = setOf(TasteFeedback.SOUR), history = history))
        assertEquals(21.0, analysis.suggestedGrind!!, 0.0)
    }

    @Test fun sourPlusBitterMeansUnevenExtraction() {
        val analysis = BrewAnalyzer.analyze(input(kasuya(), simulate(kasuya(), until = 210.0), 210.0,
            feedback = setOf(TasteFeedback.SOUR, TasteFeedback.BITTER)))
        assertEquals(ExtractionLean.UNEVEN, analysis.lean)
        assertEquals("evenness", analysis.suggestions.first().key)
    }

    @Test fun perfectKeepsSettings() {
        val analysis = BrewAnalyzer.analyze(input(kasuya(), simulate(kasuya(), until = 210.0), 210.0,
            grinder = GrinderContext("Comandante C40", comandante, 23.0), feedback = setOf(TasteFeedback.PERFECT)))
        assertEquals(listOf("repeat"), analysis.suggestions.map { it.key })
        assertEquals(23.0, analysis.suggestedGrind!!, 0.0)
    }

    @Test fun coldWaterOnLightRoastSuggestsHotter() {
        val analysis = BrewAnalyzer.analyze(input(kasuya(), simulate(kasuya(), until = 210.0), 210.0, temp = 86.0,
            feedback = setOf(TasteFeedback.SOUR)))
        assertTrue(analysis.suggestions.any { it.key == "temp-up" && it.evidence.isNotEmpty() })
        assertTrue(analysis.findings.any { it.title.contains("Cool water") })
    }

    @Test fun withoutGrinderGivesGenericAdvice() {
        val recipe = fastCase()
        val analysis = BrewAnalyzer.analyze(input(recipe, simulate(recipe, until = 205.0), 205.0, feedback = setOf(TasteFeedback.SOUR)))
        assertNull(analysis.suggestions.first { it.key == "grind" }.grindTarget)
        assertNull(analysis.suggestedGrind)
        assertTrue(analysis.findings.any { it.title == "No grinder selected" })
    }

    @Test fun darkRoastPaperWithLightRoastIsFlagged() {
        val analysis = BrewAnalyzer.analyze(input(kasuya(), simulate(kasuya(), until = 210.0), 210.0, filterIdealRoast = RoastLevel.DARK))
        assertTrue(analysis.findings.any { it.title.contains("Dark-roast paper") })
    }

    @Test fun weakWithTooMuchWaterBlamesRatio() {
        val samples = simulate(kasuya(), overshoot = listOf(0.0, 0.0, 0.0, 0.0, 30.0), until = 215.0)
        val analysis = BrewAnalyzer.analyze(input(kasuya(), samples, 215.0, finalWeight = 330.0, feedback = setOf(TasteFeedback.WEAK)))
        assertEquals("ratio-strength", analysis.suggestions.first().key)
    }

    @Test fun fourSixTipAndManualBrew() {
        val sour = BrewAnalyzer.analyze(input(kasuya(), simulate(kasuya(), until = 210.0), 210.0, feedback = setOf(TasteFeedback.SOUR)))
        assertTrue(sour.suggestions.any { it.key == "46-sweet" })
        val manual = BrewAnalyzer.analyze(input(kasuya(), emptyList(), 260.0, finalWeight = 300.0, feedback = setOf(TasteFeedback.BITTER), usedScale = false))
        assertTrue(manual.pours.isEmpty())
        assertEquals("grind", manual.suggestions.first().key)
    }

    @Test fun finishingRightAfterLastPourIsNotTreatedAsFast() {
        val analysis = BrewAnalyzer.analyze(input(kasuya(), simulate(kasuya(), until = 192.0), 192.0,
            grinder = GrinderContext("Comandante C40", comandante, 24.0), feedback = setOf(TasteFeedback.SOUR)))
        assertTrue(analysis.findings.any { it.title == "Drawdown not recorded" })
        assertFalse(analysis.findings.any { it.title.contains("finished fast") })
        assertTrue(analysis.suggestions.first { it.key == "grind" }.evidence.isEmpty())
    }

    @Test fun centeredFlowsFollowThePour() {
        val samples = (0..150).map { i -> WeightSample(i / 10.0, min(i / 10.0, 10.0) * 6) }
        val flows = BrewAnalyzer.centeredFlows(samples)
        assertEquals(6.0, flows[50], 0.01)
        assertEquals(0.0, flows[140], 0.01)
        assertTrue(flows[100] in 1.0..5.0)
        assertTrue(BrewAnalyzer.centeredFlows(emptyList()).isEmpty())
    }
}

class GrindRecommenderTest {
    private val grinder = Equipment(name = "Comandante C40", type = EquipmentType.GRINDER, grinder = GrinderSpec(GrindUnit.CLICKS, 1.0, 2.0))
    private fun brew(bean: String?, grind: Double, daysAgo: Int, recipe: String = "kasuya-46", feedback: Set<TasteFeedback> = emptySet(),
                     rating: Int = 0, suggested: Double? = null) = Brew(
        date = System.currentTimeMillis() - daysAgo * 86_400_000L, recipeId = recipe, grinderId = grinder.id,
        grinderSpec = grinder.grinder, grindValue = grind, feedback = feedback, rating = rating, suggestedGrind = suggested, beanId = bean,
    )

    @Test fun noHistoryNoRecommendation() {
        assertNull(GrindRecommender.recommend(null, grinder, "kasuya-46", emptyList()))
        assertNull(GrindRecommender.recommend(null, null, "kasuya-46", emptyList()))
    }

    @Test fun usesSuggestionFromLastReview() {
        val r = GrindRecommender.recommend("bean", grinder, "kasuya-46", listOf(
            brew("bean", 24.0, 1, feedback = setOf(TasteFeedback.SOUR), rating = 2, suggested = 22.0),
            brew("bean", 26.0, 3, feedback = setOf(TasteFeedback.SOUR), rating = 1),
        ))!!
        assertEquals(22.0, r.value, 0.0)
        assertTrue(r.reason.contains("Suggested"))
    }

    @Test fun perfectBrewIsReference() {
        val r = GrindRecommender.recommend("bean", grinder, "kasuya-46", listOf(brew("bean", 23.0, 1, feedback = setOf(TasteFeedback.PERFECT), rating = 5)))!!
        assertEquals(23.0, r.value, 0.0)
        assertTrue(r.reason.contains("reference"))
    }

    @Test fun fallsBackToRecipeAndUsesItsSuggestion() {
        val r = GrindRecommender.recommend(null, grinder, "kasuya-46", listOf(
            brew(null, 18.0, 1, recipe = "rao-v60"),
            brew(null, 24.0, 2, feedback = setOf(TasteFeedback.SOUR), suggested = 20.0),
        ))!!
        assertEquals(20.0, r.value, 0.0)
        assertTrue(r.reason.contains("of this recipe"))
    }
}

/** The live engine with a fake clock and a fake scale: auto-start, buffered target ping, step chime. */
class BrewSessionTest {
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

    @Test fun autoStartsPingsBeforeTargetAndChimesNextStep() {
        val recipe = RecipeLibrary.parse(File("../../Shared/recipes.json").readText()).first { it.id == "everyday-3-pour" }
        var now = 0L
        val cues = mutableListOf<Pair<Long, BrewCue>>()
        val scale = FakeScale()
        val session = BrewSession(recipe, scale, { AppSettings() }, { cues += now to it }, clock = { now })

        session.ready()
        assertEquals(listOf("prepare"), scale.commands)
        // Scale reports zero, then the first pour starts at 1.0 s with 5 g/s.
        var weight = 0.0
        repeat(150) { step ->
            now = step * 100L
            if (now >= 1_000 && weight < 51) weight += 0.5
            session.ingest(weight, now)
            session.tick()
        }
        assertEquals(BrewPhase.BREWING, session.phase)
        assertTrue("timer started on the scale", "start" in scale.commands)
        // Bloom target is 50 g: the ping must come before 50 g is reached (buffer ≥ 1.5 g).
        val ping = cues.first { it.second == BrewCue.TARGET }
        assertTrue("pinged before the target", ping.first < 1_000 + 10_000)
        // Next step (0:30) chimes once.
        repeat(200) { step ->
            now = 15_000L + step * 100L
            session.ingest(weight, now)
            session.tick()
        }
        assertEquals(1, cues.count { it.second == BrewCue.NEXT_STEP })
        session.finish()
        assertEquals(BrewPhase.FINISHED, session.phase)
        assertTrue("stop" in scale.commands)
    }

    @Test fun slopeEstimatesFlowRate() {
        val readings = (0 until 12).map { i -> (i * 100L) to i * 0.5 }
        assertEquals(5.0, BrewSession.slope(readings, 1.2, 1_100L), 0.01)
        assertEquals(0.0, BrewSession.slope(emptyList(), 1.2, 0L), 0.0)
    }
}
