package com.brewlog.app

import com.brewlog.app.domain.BrewMethod
import com.brewlog.app.domain.StepKind
import com.brewlog.app.machine.GaggiMateProfileImport
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GaggiMateProfileImportTest {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private val gaggiMateProfile = """
    { "id": "abc123", "label": "Blooming Shot", "type": "pro", "description": "Slow bloom, then 9 bar.",
      "temperature": 94, "dose": 18.5,
      "phases": [
        { "name": "Fill", "phase": "preinfusion", "valve": 1, "duration": 4,
          "pump": { "target": "flow", "pressure": 3, "flow": 4 } },
        { "name": "Bloom", "phase": "preinfusion", "valve": 0, "duration": 6, "pump": 0 },
        { "name": "Extraction", "phase": "brew", "valve": 1, "duration": 40,
          "pump": { "target": "pressure", "pressure": 9, "flow": 0 },
          "targets": [ { "type": "volumetric", "operator": "gte", "value": 40 } ] }
      ] }
    """

    @Test
    fun testGaggiMateProfileBecomesEspressoRecipe() {
        val element = json.parseToJsonElement(gaggiMateProfile)
        assertTrue(GaggiMateProfileImport.looksLikeProfiles(element))
        val recipes = GaggiMateProfileImport.recipes(element)
        assertEquals(1, recipes.size)
        val recipe = recipes.first()
        assertEquals("gaggimate-abc123", recipe.id)
        assertEquals("Blooming Shot", recipe.name)
        assertEquals(BrewMethod.ESPRESSO, recipe.method)
        assertEquals(18.5, recipe.dose, 0.001)
        assertEquals(40.0, recipe.water, 0.001)
        assertEquals(94.0, recipe.temperature, 0.001)
        assertEquals(9.0, recipe.pressure ?: 0.0, 0.001)
        assertEquals(true, recipe.isCustom)
        assertEquals(listOf(StepKind.PREINFUSE, StepKind.EXTRACT), recipe.steps.map { it.kind })
        assertEquals(10.0, recipe.steps.last().time, 0.001) // extraction starts after both pre-infusion phases
        assertEquals(40.0, recipe.steps.last().target ?: 0.0, 0.001)
        assertEquals(35.0, recipe.targetTime, 0.001) // with a target weight the duration is only a cap
        assertEquals(3, recipe.tips.size)
        assertEquals("Phase 1: Fill · 4 s · 4 ml/s, max 3 bar", recipe.tips.first())
        assertEquals("Phase 3: Extraction · 40 s · 9 bar · to 40 g", recipe.tips.last())
    }

    @Test
    fun testGaggiMateProfileListSkipsUtilityAndDefaults() {
        val jsonStr = """
        { "profiles": [
          { "id": "f1", "label": "Flush", "utility": true, "phases": [ { "phase": "brew", "duration": 5, "pump": 100 } ] },
          { "label": "BrewLog · Classic", "type": "standard",
            "phases": [ { "name": "Brew", "phase": "brew", "duration": 28, "pump": 100 } ] }
        ] }
        """
        val element = json.parseToJsonElement(jsonStr)
        assertTrue(GaggiMateProfileImport.looksLikeProfiles(element))
        val recipes = GaggiMateProfileImport.recipes(element)
        assertEquals(listOf("Classic"), recipes.map { it.name }) // utility profile skipped, BrewLog prefix removed
        val recipe = recipes.first()
        assertEquals("gaggimate-classic", recipe.id)
        assertEquals(18.0, recipe.dose, 0.001)
        assertEquals(36.0, recipe.water, 0.001)
        assertEquals(28.0, recipe.targetTime, 0.001)
        assertEquals(9.0, recipe.pressure ?: 0.0, 0.001)
        assertEquals(listOf(StepKind.EXTRACT), recipe.steps.map { it.kind })
        assertEquals(listOf("Phase 1: Brew · 28 s · pump 100 %"), recipe.tips)
    }

    @Test
    fun testGaggiMateDetectionLeavesRecipeFilesAlone() {
        assertFalse(GaggiMateProfileImport.looksLikeProfiles(JsonObject(emptyMap())))
        assertFalse(GaggiMateProfileImport.looksLikeProfiles(JsonObject(mapOf("BREWS" to JsonArray(emptyList())))))
        assertFalse(GaggiMateProfileImport.looksLikeProfiles(JsonArray(emptyList())))
    }

    private fun listResponse(jsonStr: String): JsonObject {
        return json.parseToJsonElement(jsonStr) as JsonObject
    }

    private val brewPhase = """{ "name": "Brew", "phase": "brew", "valve": 1, "duration": 28, "pump": 100 }"""

    @Test
    fun testSummariesUseSelectedFlag() {
        val response = listResponse("""
        { "tp": "res:profiles:list", "profiles": [
          { "id": "a", "label": "Turbo", "phases": [$brewPhase] },
          { "id": "b", "label": "Turbo", "selected": true, "phases": [$brewPhase] } ] }
        """)
        val summaries = GaggiMateProfileImport.summaries(response)
        assertEquals("b", summaries.first().id)
        assertEquals(listOf("b"), summaries.filter { it.isSelected }.map { it.id })
    }

    @Test
    fun testSummariesOrderAndSkip() {
        val response = listResponse("""
        { "profiles": [
          { "id": "x", "label": "Plain", "phases": [$brewPhase] },
          { "id": "y", "label": "Fav", "favorite": true, "phases": [$brewPhase] },
          { "id": "z", "label": "Flush", "utility": true, "phases": [$brewPhase] },
          { "label": "No id", "phases": [$brewPhase] },
          { "id": "c", "label": "BrewLog · Classic", "phases": [$brewPhase] } ] }
        """)
        val summaries = GaggiMateProfileImport.summaries(response)
        assertEquals(listOf("y", "x", "c"), summaries.map { it.id })
        val own = summaries.last()
        assertTrue(own.isBrewLogs)
        assertEquals("Classic", own.label)
        assertTrue(summaries[0].isFavorite)
        assertNotNull(summaries[0].recipe)
    }

    @Test
    fun testRatioTargetSetsYield() {
        val profile = listResponse("""
        { "label": "Long", "dose": 18, "phases": [
          { "name": "Brew", "phase": "brew", "valve": 1, "duration": 40,
            "pump": { "target": "pressure", "pressure": 9, "flow": 0 },
            "targets": [ { "type": "ratio", "value": 2.5 } ] } ] }
        """)
        val recipe = GaggiMateProfileImport.recipe(profile)
        assertNotNull(recipe)
        assertEquals(45.0, recipe!!.water, 0.001)
        assertEquals(25.0, recipe.targetTime, 0.001)
    }

    @Test
    fun testYieldIsNotRounded() {
        val profile = listResponse("""
        { "label": "Exact", "dose": 18.3, "phases": [
          { "name": "Brew", "phase": "brew", "valve": 1, "duration": 30, "pump": 100,
            "targets": [ { "type": "volumetric", "value": 36.5 } ] } ] }
        """)
        assertEquals(36.5, GaggiMateProfileImport.recipe(profile)!!.water, 0.001)

        val ratio = listResponse("""
        { "label": "Ratio", "dose": 18.3, "phases": [
          { "name": "Brew", "phase": "brew", "valve": 1, "duration": 30, "pump": 100,
            "targets": [ { "type": "ratio", "value": 2 } ] } ] }
        """)
        assertEquals(36.6, GaggiMateProfileImport.recipe(ratio)!!.water, 0.001)
    }

    @Test
    fun testFlowHoldIsLabelledFlow() {
        val profile = listResponse("""
        { "label": "Flow", "phases": [
          { "name": "Steady", "phase": "brew", "valve": 1, "duration": 20,
            "pump": { "target": "flow", "pressure": 9, "flow": -1 } } ] }
        """)
        val tip = GaggiMateProfileImport.recipe(profile)!!.tips.first()
        assertTrue(tip.contains("hold flow"))
        assertFalse(tip.contains("hold pressure"))
    }

    @Test
    fun testHoldPressureIsIgnored() {
        val profile = listResponse("""
        { "label": "Hold", "phases": [
          { "name": "Pre", "phase": "preinfusion", "valve": 1, "duration": 5,
            "pump": { "target": "pressure", "pressure": 3, "flow": 0 } },
          { "name": "Hold", "phase": "brew", "valve": 1, "duration": 10,
            "pump": { "target": "pressure", "pressure": -1, "flow": -1 } },
          { "name": "Ramp", "phase": "brew", "valve": 1, "duration": 20,
            "pump": { "target": "pressure", "pressure": 6, "flow": 0 } } ] }
        """)
        val recipe = GaggiMateProfileImport.recipe(profile)!!
        assertEquals(6.0, recipe.pressure ?: 0.0, 0.001)
        val tip = recipe.tips.first { it.contains("Hold ·") }
        assertTrue(tip.contains("hold"))
    }
}
