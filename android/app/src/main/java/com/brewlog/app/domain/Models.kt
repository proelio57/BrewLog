package com.brewlog.app.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max

// Port of BrewLog/Models/Models.swift (value types + persisted records).

@Serializable
enum class RoastLevel(val displayName: String) {
    @SerialName("light") LIGHT("Light"),
    @SerialName("mediumLight") MEDIUM_LIGHT("Medium-light"),
    @SerialName("medium") MEDIUM("Medium"),
    @SerialName("mediumDark") MEDIUM_DARK("Medium-dark"),
    @SerialName("dark") DARK("Dark");

    /** 0 = lightest, 4 = darkest */
    val index: Int get() = ordinal
}

@Serializable
enum class ProcessMethod(val displayName: String) {
    @SerialName("washed") WASHED("Washed"),
    @SerialName("natural") NATURAL("Natural"),
    @SerialName("honey") HONEY("Honey"),
    @SerialName("anaerobic") ANAEROBIC("Anaerobic"),
    @SerialName("other") OTHER("Other"),
}

@Serializable
enum class EquipmentType(val displayName: String) {
    @SerialName("brewer") BREWER("Brewers"),
    @SerialName("grinder") GRINDER("Grinders"),
    @SerialName("kettle") KETTLE("Kettles"),
    @SerialName("filter") FILTER("Filters"),
    @SerialName("scale") SCALE("Scales"),
    @SerialName("water") WATER("Water"),
}

/** How fast water passes through a filter paper. This has a big effect on drawdown time. */
@Serializable
enum class FilterFlow(val displayName: String) {
    @SerialName("fast") FAST("Fast"),
    @SerialName("medium") MEDIUM("Medium"),
    @SerialName("slow") SLOW("Slow"),
}

enum class PaperShape { CONE, FLAT, CHEMEX }

/** How a grinder's setting is expressed. */
@Serializable
enum class GrindUnit(val displayName: String, val suffix: String) {
    @SerialName("clicks") CLICKS("Clicks", "clicks"),
    @SerialName("numbers") NUMBERS("Numbers", ""),
    @SerialName("dial") DIAL("Dial", ""),
    @SerialName("microns") MICRONS("Microns", "µm"),
}

/** A grinder's adjustment scale, so suggestions can be concrete ("try 22 clicks"). */
@Serializable
data class GrinderSpec(
    val unit: GrindUnit = GrindUnit.CLICKS,
    /** Smallest increment, e.g. 1 click or 0.1 on a dial. */
    val step: Double = 1.0,
    /** What a sensible small adjustment is for this grinder. */
    val adjustStep: Double = 2.0,
    /** Most grinders get finer as the number goes down. */
    val finerIsLower: Boolean = true,
    /** Typical pour-over range, e.g. "20–30 clicks" (informational). */
    val rangeNote: String = "",
    /** Sensible starting default for pour-over / filter brew. */
    val defaultGrind: Double? = null,
) {
    private val decimals: Int get() = if (step < 1) (if (step < 0.1) 2 else 1) else 0

    fun format(value: Double): String {
        val number = String.format(Locale.US, "%.${decimals}f", value)
        return if (unit.suffix.isEmpty()) number else "$number ${unit.suffix}"
    }

    fun formatDelta(delta: Double): String {
        val number = String.format(Locale.US, "%.${decimals}f", abs(delta))
        return when (unit) {
            GrindUnit.CLICKS -> "$number click" + if (abs(delta) == 1.0) "" else "s"
            GrindUnit.MICRONS -> "$number µm"
            GrindUnit.NUMBERS, GrindUnit.DIAL -> number
        }
    }

    /** Moves [value] by adjustment steps toward finer or coarser, snapped to [step]. */
    fun adjusted(value: Double, coarser: Boolean, multiplier: Double = 1.0): Double {
        val delta = adjustStep * multiplier
        val signed = if (coarser == finerIsLower) delta else -delta
        val snapped = roundHalfAway((value + signed) / step) * step
        return max(0.0, snapped)
    }

    /** Default starting grind for this grinder (explicit default, parsed range midpoint, or unit fallback). */
    fun defaultStartingValue(): Double {
        if (defaultGrind != null) return defaultGrind
        val match = Regex("(\\d+(?:\\.\\d+)?)[–-](\\d+(?:\\.\\d+)?)").find(rangeNote)
        if (match != null) {
            val low = match.groupValues[1].toDoubleOrNull()
            val high = match.groupValues[2].toDoubleOrNull()
            if (low != null && high != null && high >= low) {
                val mid = (low + high) / 2.0
                return roundHalfAway(mid / step) * step
            }
        }
        return when (unit) {
            GrindUnit.CLICKS -> 20.0
            GrindUnit.NUMBERS -> if (step < 1.0) 6.0 else 15.0
            GrindUnit.DIAL -> if (step < 1.0) 5.0 else 5.0
            GrindUnit.MICRONS -> 600.0
        }
    }
}

@Serializable
data class WeightSample(
    /** Seconds since brew start. */
    val t: Double,
    /** Grams on the scale. */
    val w: Double,
)

/**
 * Espresso: one reading from the machine (GaggiMate) or the pressure sensor during a shot.
 * Same JSON as iOS and web: {"t": seconds, "p": bar, "c": °C, "f": ml/s}. Stored per brew next to the weight curve.
 */
@Serializable
data class MachineSample(
    val t: Double,
    val p: Double,
    val c: Double? = null,
    val f: Double? = null,
)

@Serializable
data class PressureSample(
    /** Seconds since brew/shot start. */
    val t: Double,
    /** Extraction pressure in bar. */
    val bar: Double,
)

@Serializable
enum class TasteFeedback(val title: String, val subtitle: String) {
    @SerialName("perfect") PERFECT("Perfect", "Sweet, balanced, would brew again"),
    @SerialName("sour") SOUR("Too sour", "Sharp, salty, thin, short finish"),
    @SerialName("bitter") BITTER("Too bitter", "Harsh, burnt, lingering bitterness"),
    @SerialName("weak") WEAK("Too weak", "Watery, lacking flavour"),
    @SerialName("strong") STRONG("Too strong", "Heavy, intense, muddy"),
    @SerialName("astringent") ASTRINGENT("Dry / astringent", "Drying, rough, mouth-puckering"),
    @SerialName("flat") FLAT("Flat / dull", "Lifeless, hollow, no sparkle"),
}

@Serializable
data class Bean(
    val id: String = newId(),
    val name: String = "",
    val roaster: String = "",
    val origin: String = "",
    val varietal: String = "",
    val process: ProcessMethod = ProcessMethod.WASHED,
    val roastLevel: RoastLevel = RoastLevel.LIGHT,
    /** Epoch millis. */
    val roastDate: Long? = null,
    val tastingNotes: String = "",
    val notes: String = "",
    val bagWeight: Double = 250.0,
    val remaining: Double = 250.0,
    val isArchived: Boolean = false,
    val externalId: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
) {
    val displayName: String get() = if (roaster.isEmpty()) name else "$name · $roaster"

    fun daysOffRoast(now: Long = System.currentTimeMillis()): Int? =
        roastDate?.let { ((now - it) / 86_400_000L).toInt() }
}

@Serializable
data class Equipment(
    val id: String = newId(),
    val name: String,
    val type: EquipmentType,
    val notes: String = "",
    /** Brewers only. */
    val method: BrewMethod? = null,
    /** Filters only: flow speed of the paper. */
    val filterFlow: FilterFlow? = null,
    /** Filters only: roast level the paper is designed for (e.g. CAFEC roast-specific papers). */
    val idealRoast: RoastLevel? = null,
    /** Grinders only: adjustment scale. */
    val grinder: GrinderSpec = GrinderSpec(),
    val externalId: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
) {
    val subtitle: String
        get() = when (type) {
            EquipmentType.FILTER -> listOfNotNull(
                filterFlow?.let { "${it.displayName} flow" },
                idealRoast?.let { "for ${it.displayName.lowercase()} roasts" },
            ).joinToString(" · ")
            EquipmentType.GRINDER -> "Adjust in steps of ${grinder.formatDelta(grinder.adjustStep)}" +
                if (grinder.rangeNote.isEmpty()) "" else " · pour-over ${grinder.rangeNote}"
            EquipmentType.BREWER -> method?.displayName ?: ""
            else -> notes
        }
}

@Serializable
data class Brew(
    val id: String = newId(),
    val date: Long = System.currentTimeMillis(),
    val recipeId: String = "",
    val recipeName: String = "",
    /** Snapshot of the (scaled) recipe used. */
    val recipe: Recipe? = null,
    val dose: Double = 0.0,
    val targetWater: Double = 0.0,
    val finalWeight: Double = 0.0,
    val totalTime: Double = 0.0,
    val waterTemp: Double = 0.0,
    /** Free-text grind (used when no grinder is selected). */
    val grindSetting: String = "",
    /** Numeric grind on the selected grinder's scale. */
    val grindValue: Double? = null,
    /** Grind suggested by the analysis after reviewing. Pre-filled next time. */
    val suggestedGrind: Double? = null,
    val brewerId: String? = null,
    val brewerName: String = "",
    val grinderId: String? = null,
    val grinderName: String = "",
    /** Snapshot of the grinder scale, so formatting and analysis survive deleting the grinder. */
    val grinderSpec: GrinderSpec? = null,
    val filterId: String? = null,
    val filterName: String = "",
    val filterFlow: FilterFlow? = null,
    val filterIdealRoast: RoastLevel? = null,
    val beanId: String? = null,
    val usedScale: Boolean = false,
    val rating: Int = 0,
    val feedback: Set<TasteFeedback> = emptySet(),
    val notes: String = "",
    val externalId: String? = null,
    /** Weight curve. Stored in a separate file per brew (see BrewRepository), not in the main data file. */
    @Transient val samples: List<WeightSample> = emptyList(),
    /** Pressure curve in bar (if pressure monitor was connected). */
    @Transient val pressureSamples: List<PressureSample> = emptyList(),
) {
    val ratio: Double get() = if (dose > 0) finalWeight / dose else 0.0
    val isReviewed: Boolean get() = rating > 0 || feedback.isNotEmpty()

    /** Human readable grind, e.g. "24 clicks" or the free text. */
    val grindDisplay: String
        get() = grindValue?.let { (grinderSpec ?: GrinderSpec()).format(it) } ?: grindSetting
}

/** Everything the app stores (except weight curves, which live in one file per brew). */
@Serializable
data class AppData(
    val version: Int = 1,
    val beans: List<Bean> = emptyList(),
    val equipment: List<Equipment> = emptyList(),
    val brews: List<Brew> = emptyList(),
    val customRecipes: List<Recipe> = emptyList(),
)

enum class PingLeadMode(val raw: String, val title: String) {
    AUTO("auto", "Automatic (flow based)"),
    FIXED("fixed", "Fixed grams"),
}

data class AppSettings(
    val autoStartThreshold: Double = 1.5,
    val pingLeadMode: PingLeadMode = PingLeadMode.AUTO,
    val pingLeadGrams: Double = 3.0,
    val reactionTime: Double = 0.6,
    val soundEnabled: Boolean = true,
    val hapticsEnabled: Boolean = true,
    val soundVolume: Double = 0.8,
    val silentModeSound: Boolean = true,
    val countdownTicks: Boolean = false,
    /** With a scale, a brew starts by weighing the beans (can be skipped). */
    val weighBeansFirst: Boolean = true,
    /** Hario Switch: 3-2-1 ticks before the valve opens or closes, even when ticks before every step are off. */
    val valveCountdown: Boolean = true,
    val voicePrompts: Boolean = false,
    /** Announce the next step a few seconds ahead. */
    val voicePreview: Boolean = true,
    /** Recipe list filter by brewer type (raw value, "" = all). */
    val recipeFilter: String = "",
    val finishPing: Boolean = true,
    val keepAwake: Boolean = true,
    val onboardingDone: Boolean = false,
    val setupBannerDismissed: Boolean = false,
    val quickWeighAutoStart: Boolean = true,
    val chartShowsFlow: Boolean = true,
    val onlineRecipes: Boolean = true,
    val espressoPressureEnabled: Boolean = false,
)
