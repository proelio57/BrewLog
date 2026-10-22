package com.brewlog.app

import com.brewlog.app.domain.BrewMethod
import com.brewlog.app.domain.EquipmentPreset
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.domain.Extraction
import com.brewlog.app.domain.GrindConverter
import com.brewlog.app.domain.GrindUnit
import com.brewlog.app.domain.GrinderSpec
import com.brewlog.app.domain.RecipeLibrary
import com.brewlog.app.domain.WaterChemistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Same scenarios and numbers as ToolsTests.swift (extraction, water, grind conversion). */
class ToolsTest {
    // MARK: Extraction

    @Test fun extractionYield() {
        // 15 g coffee, 220 g in the cup at 1.35 % TDS → 19.8 %
        assertEquals(19.8, Extraction.yield(1.35, 220.0, 15.0)!!, 0.001)
        assertNull(Extraction.yield(0.0, 220.0, 15.0))
        assertNull(Extraction.yield(1.3, 220.0, 0.0))
    }

    @Test fun estimatedBeverage() {
        assertEquals(220.0, Extraction.estimatedBeverage(250.0, 15.0, espresso = false), 0.0)
        assertEquals(36.0, Extraction.estimatedBeverage(36.0, 18.0, espresso = true), 0.0)
        assertEquals(0.0, Extraction.estimatedBeverage(10.0, 15.0, espresso = false), 0.0)
    }

    @Test fun extractionVerdicts() {
        val ideal = Extraction.evaluate(1.35, 220.0, 15.0, espresso = false)!!
        assertEquals(Extraction.Verdict.IDEAL, ideal.verdict)
        assertEquals(Extraction.Strength.IDEAL, ideal.strength)

        val under = Extraction.evaluate(1.1, 220.0, 15.0, espresso = false)!!
        assertEquals(Extraction.Verdict.UNDER, under.verdict)
        assertEquals(Extraction.Strength.WEAK, under.strength)
        assertTrue(under.advice.contains("grind finer"))

        val espresso = Extraction.evaluate(10.0, 36.0, 18.0, espresso = true)!!
        assertEquals(20.0, espresso.yield, 0.001)
        assertEquals(Extraction.Verdict.IDEAL, espresso.verdict)

        val over = Extraction.evaluate(12.5, 36.0, 18.0, espresso = true)!!
        assertEquals(Extraction.Verdict.OVER, over.verdict)
        assertEquals(Extraction.Strength.STRONG, over.strength)
    }

    // MARK: Water

    @Test fun waterMineralsMatchBaristaHustleConcentrates() {
        assertEquals(2.45, WaterChemistry.EPSOM_PER_PPM, 0.02)
        assertEquals(1.68, WaterChemistry.BAKING_SODA_PER_PPM, 0.01)
        assertEquals(1.47, WaterChemistry.CALCIUM_CHLORIDE_PER_PPM, 0.01)
    }

    @Test fun waterRecipe() {
        val sca = WaterChemistry.Recipe(68.0, 40.0, 4.0)
        assertEquals(68 * 2.4625 * 4 / 1000, sca.epsomGrams, 0.001)
        assertEquals(0.0, sca.calciumChlorideGrams, 0.0)
        assertEquals(40 * 1.6786 * 4 / 1000, sca.bakingSodaGrams, 0.001)
        assertEquals(272.0, sca.hardnessConcentrateGrams, 0.0001)
        assertEquals(160.0, sca.bufferConcentrateGrams, 0.0001)
        assertEquals(4000.0 - 272 - 160, sca.distilledGrams, 0.0001)

        val mixed = WaterChemistry.Recipe(100.0, 0.0, 1.0, magnesiumShare = 0.5)
        assertEquals(50 * WaterChemistry.EPSOM_PER_PPM / 1000, mixed.epsomGrams, 0.0001)
        assertEquals(50 * WaterChemistry.CALCIUM_CHLORIDE_PER_PPM / 1000, mixed.calciumChlorideGrams, 0.0001)
        assertEquals(100.0, mixed.hardnessConcentrateGrams + mixed.calciumConcentrateGrams, 0.0001)
    }

    @Test fun waterInputsAreClamped() {
        val silly = WaterChemistry.Recipe(99_999.0, -5.0, 1_000.0, magnesiumShare = 3.0)
        assertEquals(WaterChemistry.MAX_PPM * WaterChemistry.MAX_LITRES, silly.hardnessConcentrateGrams, 0.0001)
        assertEquals(0.0, silly.bakingSodaGrams, 0.0)
        assertEquals(0.0, silly.calciumChlorideGrams, 0.0)
        assertTrue(silly.distilledGrams >= 0)
    }

    @Test fun waterPresetsAndCharacter() {
        assertEquals(WaterChemistry.presets.size, WaterChemistry.presets.map { it.name }.toSet().size)
        assertEquals("GH 68 · KH 40 ppm", WaterChemistry.summary(68.0, 40.0))
        assertTrue(WaterChemistry.character(0.0, 0.0).contains("Add minerals"))
        assertTrue(WaterChemistry.character(100.0, 10.0).contains("bright"))
    }

    // MARK: Grind conversion

    private val comandante = GrinderSpec(unit = GrindUnit.CLICKS, step = 1.0, adjustStep = 2.0, defaultGrind = 24.0, micronsPerStep = 30.0)
    private val kUltra = GrinderSpec(unit = GrindUnit.NUMBERS, step = 0.1, adjustStep = 0.2, defaultGrind = 7.5, micronsPerStep = 20.0)

    @Test fun convertsBetweenGrinders() {
        assertEquals(7.5, GrindConverter.convert(24.0, comandante, kUltra)!!, 0.0001)
        // 2 clicks finer = 60 µm = 3 steps of 0.1 on the K-Ultra
        assertEquals(7.2, GrindConverter.convert(22.0, comandante, kUltra)!!, 0.0001)
        assertEquals(26.0, GrindConverter.convert(7.8, kUltra, comandante)!!, 0.0001)
        assertEquals(720.0, GrindConverter.microns(24.0, comandante)!!, 0.0)
    }

    @Test fun conversionNeedsCalibration() {
        val unknown = GrinderSpec(unit = GrindUnit.DIAL, step = 1.0, adjustStep = 1.0, defaultGrind = 5.0)
        assertFalse(GrindConverter.canConvert(unknown))
        assertNull(GrindConverter.convert(5.0, unknown, comandante))
        assertEquals(30.0, GrindConverter.calibrated(GrinderSpec(defaultGrind = 24.0), "Comandante C40").micronsPerStep!!, 0.0)
        assertEquals(25.0, GrindConverter.calibrated(GrinderSpec(micronsPerStep = 25.0), "Comandante C40").micronsPerStep!!, 0.0)
        assertEquals(10.0, GrindConverter.calibrated(GrinderSpec(unit = GrindUnit.MICRONS, step = 10.0), "Lab grinder").micronsPerStep!!, 0.0)
        assertTrue(EquipmentPreset.all.any { it.type == EquipmentType.GRINDER && it.grinder?.let { g -> GrindConverter.canConvert(GrindConverter.calibrated(g, it.name)) } == true })
    }

    @Test fun coarserWhenLowerGrinder() {
        assertEquals(26.0, GrindConverter.convert(22.0, comandante, comandante.copy(finerIsLower = false))!!, 0.0001)
    }

    @Test fun recipeGrindHint() {
        assertEquals(600.0..750.0, GrindConverter.micronRange("Medium-fine (roughly 600–750 µm, e.g. Comandante 22–25 clicks)"))
        assertEquals(750.0..750.0, GrindConverter.micronRange("Medium (approx. 750 µm)"))
        assertNull(GrindConverter.micronRange("Fine (espresso). Adjust so the shot takes 25–30 s."))
        assertEquals("≈ 20–25 clicks", GrindConverter.hint("about 600–750 µm", comandante))
        assertEquals("≈ 7.5", GrindConverter.hint("approx. 720 µm", kUltra))
        assertNull(GrindConverter.hint("about 600–750 µm", GrinderSpec()))
        val recipes = RecipeLibrary.parse(File("../../Shared/recipes.json").readText())
        for (recipe in recipes.filter { it.method != BrewMethod.ESPRESSO && !it.id.startsWith("template") }) {
            assertNotNull(recipe.id, GrindConverter.micronRange(recipe.grind))
        }
    }
}
