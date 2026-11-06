package com.brewlog.app.domain

import kotlin.math.roundToInt

/**
 * Brewing water made from distilled / reverse-osmosis water and minerals. Hardness (GH) and alkalinity (KH) are in
 * mg/L (ppm) as CaCO3. Epsom salt (MgSO4·7H2O) and calcium chloride (CaCl2·2H2O) for hardness, baking soda (NaHCO3)
 * for the buffer. Concentrates follow Barista Hustle: 1000 ppm each, so 1 g per litre adds 1 ppm. Port of WaterChemistry.swift.
 */
object WaterChemistry {
    /** Milligrams of mineral per litre for 1 mg/L as CaCO3 (molar mass ratios; bicarbonate counts half). */
    const val EPSOM_PER_PPM = 246.47 / 100.09
    const val CALCIUM_CHLORIDE_PER_PPM = 147.01 / 100.09
    const val BAKING_SODA_PER_PPM = 2 * 84.007 / 100.09

    const val MAX_PPM = 500.0
    const val MAX_LITRES = 50.0

    data class Profile(val name: String, val hardness: Double, val alkalinity: Double, val note: String = "")

    val presets = listOf(
        Profile("SCA standard", 68.0, 40.0, "The SCA target for brewing water: 68 ppm hardness, 40 ppm alkalinity."),
        Profile("Rao", 76.0, 50.0, "Close to Scott Rao's recommendation. A bit more buffer, rounder and less bright."),
        Profile("Barista Hustle", 81.0, 40.0, "Barista Hustle's original recipe. Lots of hardness for sweetness and body."),
        Profile("Hendon", 100.0, 31.0, "Centre of Hendon's and Colonna-Dashwood's ideal zone. High hardness, low buffer, very bright."),
        Profile("World of Coffee Budapest", 51.0, 40.0, "Competition water. Balanced and clean."),
        Profile("Melbourne", 24.0, 12.0, "Very soft, like Melbourne tap water. Clear and delicate, great for light roasts."),
    )

    /** [magnesiumShare]: 0 = only calcium chloride, 1 = only Epsom salt (brighter vs rounder). */
    data class Recipe(val hardness: Double, val alkalinity: Double, val litres: Double, val magnesiumShare: Double = 1.0) {
        private val h get() = hardness.clamped(0.0, MAX_PPM)
        private val a get() = alkalinity.clamped(0.0, MAX_PPM)
        private val l get() = litres.clamped(0.0, MAX_LITRES)
        private val mg get() = magnesiumShare.clamped(0.0, 1.0)

        /** Grams of dry mineral to dissolve directly in [litres] of water. */
        val epsomGrams get() = h * mg * EPSOM_PER_PPM * l / 1000
        val calciumChlorideGrams get() = h * (1 - mg) * CALCIUM_CHLORIDE_PER_PPM * l / 1000
        val bakingSodaGrams get() = a * BAKING_SODA_PER_PPM * l / 1000

        /** Grams of each 1000 ppm concentrate, topped up with distilled water to [litres]. */
        val hardnessConcentrateGrams get() = h * mg * l
        val calciumConcentrateGrams get() = h * (1 - mg) * l
        val bufferConcentrateGrams get() = a * l
        val distilledGrams get() = maxOf(l * 1000 - hardnessConcentrateGrams - calciumConcentrateGrams - bufferConcentrateGrams, 0.0)
    }

    fun summary(hardness: Double, alkalinity: Double) = "GH ${hardness.roundToInt()} · KH ${alkalinity.roundToInt()} ppm"

    /** What the water does to the cup, from the hardness and the buffer. */
    fun character(hardness: Double, alkalinity: Double): String {
        if (hardness <= 0 && alkalinity <= 0) return "Pure water: flat, sour coffee. Add minerals."
        val parts = mutableListOf<String>()
        parts += when {
            alkalinity < 20 -> "Low buffer: bright, more acidity."
            alkalinity > 60 -> "High buffer: mutes acidity, can taste chalky."
            else -> "Moderate buffer: balanced acidity."
        }
        parts += when {
            hardness < 30 -> "Soft: clean but less sweetness and body."
            hardness > 120 -> "Very hard: heavy, can over-extract and scales machines."
            else -> "Hardness extracts sweetness well."
        }
        return parts.joinToString(" ")
    }
}
