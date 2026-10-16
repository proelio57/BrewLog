package com.brewlog.app.domain

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

// Port of BrewLog/Recipes/RecipeLibrary.swift.

object RecipeLibrary {
    val json = Json { ignoreUnknownKeys = true }

    /** Parses the shared recipes.json (same file as iOS) and validates every recipe. */
    fun parse(text: String): List<Recipe> =
        json.decodeFromString(ListSerializer(Recipe.serializer()), text).map { it.validated() }

    /** Starting point for the custom recipe editor. */
    fun blankRecipe(): Recipe = Recipe(
        id = "custom-" + newId(),
        name = "My Recipe",
        author = "Me",
        method = BrewMethod.V60,
        summary = "",
        tasteNotes = "",
        taste = TasteProfile(3, 3, 3, 3),
        dose = 15.0,
        water = 250.0,
        temperature = 94.0,
        grind = "Medium-fine",
        targetTime = 180.0,
        flowMin = 3.0,
        flowMax = 8.0,
        steps = listOf(
            RecipeStep(StepKind.BLOOM, 0.0, 45.0),
            RecipeStep(StepKind.POUR, 45.0, 150.0),
            RecipeStep(StepKind.POUR, 75.0, 250.0),
        ),
        tips = emptyList(),
        isCustom = true,
    )
}

/** Quick-add equipment presets. */
data class EquipmentPreset(
    val name: String,
    val type: EquipmentType,
    val method: BrewMethod? = null,
    val flow: FilterFlow? = null,
    val idealRoast: RoastLevel? = null,
    val grinder: GrinderSpec? = null,
    val notes: String = "",
    /** Paper shape a brewer takes / a filter has (used to show compatible papers first). */
    val shape: PaperShape? = null,
) {
    fun makeEquipment(): Equipment = Equipment(
        name = name,
        type = type,
        notes = notes,
        method = method,
        filterFlow = flow,
        idealRoast = idealRoast,
        grinder = grinder ?: GrinderSpec(),
    )

    companion object {
        private fun grinder(
            name: String,
            unit: GrindUnit,
            step: Double,
            adjust: Double,
            range: String = "",
            notes: String = "",
            defaultGrind: Double? = null,
        ) = EquipmentPreset(name, EquipmentType.GRINDER, grinder = GrinderSpec(unit, step, adjust, true, range, defaultGrind), notes = notes)

        /** Grinder scales. Ranges are typical starting points only, so they're editable. */
        val grinders: List<EquipmentPreset> = listOf(
            grinder("Comandante C40", GrindUnit.CLICKS, 1.0, 2.0, "20–30 clicks", "Clicks counted from fully closed. About 30 µm per click.", defaultGrind = 24.0),
            grinder("1Zpresso K-Ultra", GrindUnit.NUMBERS, 0.1, 0.2, notes = "Read the dial as rotation.number, e.g. 7.5.", defaultGrind = 7.5),
            grinder("1Zpresso ZP6 Special", GrindUnit.NUMBERS, 0.1, 0.2, notes = "Read the dial as rotation.number, e.g. 4.5.", defaultGrind = 4.5),
            grinder("1Zpresso J-Max", GrindUnit.CLICKS, 1.0, 5.0, notes = "Very fine steps, so adjust in bigger jumps for filter.", defaultGrind = 30.0),
            grinder("Timemore C3", GrindUnit.CLICKS, 1.0, 1.0, "about 14–20 clicks", defaultGrind = 16.0),
            grinder("Kingrinder K6", GrindUnit.CLICKS, 1.0, 5.0, notes = "Fine steps, so adjust in bigger jumps for filter.", defaultGrind = 90.0),
            grinder("Fellow Ode Gen 2", GrindUnit.DIAL, 1.0, 1.0, notes = "Dial 1–11 in steps of 1/3. Track whole numbers or enter thirds as decimals.", defaultGrind = 5.0),
            grinder("Baratza Encore ESP", GrindUnit.NUMBERS, 1.0, 2.0, defaultGrind = 20.0),
            grinder("Niche Zero", GrindUnit.DIAL, 1.0, 3.0, defaultGrind = 45.0),
            grinder("Wilfa Uniform", GrindUnit.NUMBERS, 1.0, 1.0, defaultGrind = 20.0),
            grinder("Lagom P64", GrindUnit.DIAL, 0.1, 0.2, defaultGrind = 5.5),
            grinder("Mazzer Philos", GrindUnit.DIAL, 1.0, 2.0, defaultGrind = 30.0),
            grinder("DF64 / DF83", GrindUnit.DIAL, 1.0, 3.0, defaultGrind = 50.0),
        )

        /** CAFEC roast-specific papers are named after their recommended brew temperature. */
        val filters: List<EquipmentPreset> = listOf(
            EquipmentPreset("CAFEC T-90 (Medium-Dark Roast)", EquipmentType.FILTER, flow = FilterFlow.MEDIUM, idealRoast = RoastLevel.MEDIUM_DARK,
                notes = "Two-sided crepe, smooth and steady flow, designed for 90 °C. Balanced and repeatable. Also popular for light roasts.", shape = PaperShape.CONE),
            EquipmentPreset("CAFEC T-92 (Light Roast)", EquipmentType.FILTER, flow = FilterFlow.FAST, idealRoast = RoastLevel.LIGHT,
                notes = "Low density with a deep crepe, designed for 92 °C. Clean cup with strong aroma.", shape = PaperShape.CONE),
            EquipmentPreset("CAFEC T-83 (Dark Roast)", EquipmentType.FILTER, flow = FilterFlow.MEDIUM, idealRoast = RoastLevel.DARK,
                notes = "0.22 mm, medium density, designed for 83 °C. Fast at first, then slows down. Brings body and sweetness.", shape = PaperShape.CONE),
            EquipmentPreset("CAFEC Abaca+", EquipmentType.FILTER, flow = FilterFlow.FAST,
                notes = "Abaca fibre blend. Fast flow, great clarity, an all-rounder.", shape = PaperShape.CONE),
            EquipmentPreset("CAFEC Abaca", EquipmentType.FILTER, flow = FilterFlow.FAST,
                notes = "The original abaca paper. Fast and clean.", shape = PaperShape.CONE),
            EquipmentPreset("Hario V60 standard paper", EquipmentType.FILTER, flow = FilterFlow.MEDIUM,
                notes = "The standard white V60 paper. Medium flow. Rinse well.", shape = PaperShape.CONE),
            EquipmentPreset("Hario V60 tabbed paper (Japan)", EquipmentType.FILTER, flow = FilterFlow.FAST,
                notes = "Japanese-made tabbed paper. Faster than the standard paper.", shape = PaperShape.CONE),
            EquipmentPreset("Hario V60 natural paper (unbleached)", EquipmentType.FILTER, flow = FilterFlow.MEDIUM,
                notes = "Unbleached brown paper. Rinse very well to avoid a papery taste.", shape = PaperShape.CONE),
            EquipmentPreset("Sibarist FAST Cone", EquipmentType.FILTER, flow = FilterFlow.FAST,
                notes = "Very fast specialty paper. Lets you grind finer without stalling.", shape = PaperShape.CONE),
            EquipmentPreset("Origami cone paper", EquipmentType.FILTER, flow = FilterFlow.FAST, shape = PaperShape.CONE),
            EquipmentPreset("Kalita Wave 185 paper", EquipmentType.FILTER, flow = FilterFlow.MEDIUM,
                notes = "Flat-bottom wave paper for Kalita, Orea and similar drippers.", shape = PaperShape.FLAT),
            EquipmentPreset("Sibarist FAST Flat", EquipmentType.FILTER, flow = FilterFlow.FAST,
                notes = "Flat-bottom version for Orea, April and Kalita.", shape = PaperShape.FLAT),
            EquipmentPreset("Chemex bonded paper", EquipmentType.FILTER, flow = FilterFlow.SLOW,
                notes = "Thick paper, very clean cup with lighter body. Slow drawdown, so grind coarser.", shape = PaperShape.CHEMEX),
        )

        val brewers: List<EquipmentPreset> = listOf(
            EquipmentPreset("Hario V60 02", EquipmentType.BREWER, method = BrewMethod.V60, shape = PaperShape.CONE),
            EquipmentPreset("Hario V60 01", EquipmentType.BREWER, method = BrewMethod.V60, shape = PaperShape.CONE),
            EquipmentPreset("Hario Switch 02", EquipmentType.BREWER, method = BrewMethod.HYBRID, shape = PaperShape.CONE),
            EquipmentPreset("Hario Switch 03", EquipmentType.BREWER, method = BrewMethod.HYBRID, shape = PaperShape.CONE),
            EquipmentPreset("Kalita Wave 185", EquipmentType.BREWER, method = BrewMethod.KALITA, shape = PaperShape.FLAT),
            EquipmentPreset("Origami Dripper M", EquipmentType.BREWER, method = BrewMethod.V60, shape = PaperShape.CONE),
            EquipmentPreset("Orea v4", EquipmentType.BREWER, method = BrewMethod.KALITA, shape = PaperShape.FLAT),
            EquipmentPreset("April Brewer", EquipmentType.BREWER, method = BrewMethod.KALITA, shape = PaperShape.FLAT),
            EquipmentPreset("Chemex 6-cup", EquipmentType.BREWER, method = BrewMethod.UNIVERSAL, shape = PaperShape.CHEMEX),
            EquipmentPreset("Clever Dripper", EquipmentType.BREWER, method = BrewMethod.HYBRID, shape = PaperShape.CONE),
        )

        private val others: List<EquipmentPreset> = listOf(
            EquipmentPreset("Fellow Stagg EKG", EquipmentType.KETTLE),
            EquipmentPreset("Hario Buono", EquipmentType.KETTLE),
            EquipmentPreset("Brewista Artisan", EquipmentType.KETTLE),
            EquipmentPreset("Bookoo Themis Mini", EquipmentType.SCALE),
            EquipmentPreset("Third Wave Water (light roast)", EquipmentType.WATER),
            EquipmentPreset("Filtered tap water", EquipmentType.WATER),
        )

        val all: List<EquipmentPreset> = filters + grinders + brewers + others

        /** Defaults for a custom grinder in the setup assistant. */
        fun specFor(unit: GrindUnit): GrinderSpec = when (unit) {
            GrindUnit.CLICKS -> GrinderSpec(GrindUnit.CLICKS, 1.0, 2.0, defaultGrind = 20.0)
            GrindUnit.NUMBERS -> GrinderSpec(GrindUnit.NUMBERS, 1.0, 1.0, defaultGrind = 15.0)
            GrindUnit.DIAL -> GrinderSpec(GrindUnit.DIAL, 0.1, 0.2, defaultGrind = 5.0)
            GrindUnit.MICRONS -> GrinderSpec(GrindUnit.MICRONS, 10.0, 50.0, defaultGrind = 600.0)
        }
    }
}
