package com.brewlog.app.domain


/**
 * Rough translation of grind settings between grinders. A calibrated grinder has a medium-fine filter setting
 * ([GrinderSpec.defaultGrind]) pinned at [REFERENCE_MICRONS] on a shared scale and [GrinderSpec.micronsPerStep].
 * A starting point to taste from, not an exact match. Port of GrindConverter.swift.
 */
object GrindConverter {
    /** The shared scale's point for a medium-fine filter grind (Comandante 24 clicks). */
    const val REFERENCE_MICRONS = 720.0

    /** Calibration of the grinder presets by name: µm per smallest step. */
    val knownMicronsPerStep = mapOf(
        "Comandante C40" to 30.0,
        "1Zpresso K-Ultra" to 20.0,
        "1Zpresso ZP6 Special" to 16.0,
        "Kingrinder K6" to 16.0,
    )

    /** The spec with the preset calibration filled in when the grinder has none of its own. */
    fun calibrated(spec: GrinderSpec, name: String): GrinderSpec =
        if (spec.micronsPerStep != null) spec
        else spec.copy(micronsPerStep = if (spec.unit == GrindUnit.MICRONS) spec.step else knownMicronsPerStep[name])

    fun canConvert(spec: GrinderSpec) = spec.defaultGrind != null && (spec.micronsPerStep ?: 0.0) > 0 && spec.step > 0

    /** The setting's position on the shared µm scale. */
    fun microns(value: Double, spec: GrinderSpec): Double? {
        if (!canConvert(spec)) return null
        val steps = (value - spec.defaultGrind!!) / spec.step
        return REFERENCE_MICRONS + (if (spec.finerIsLower) steps else -steps) * spec.micronsPerStep!!
    }

    /** The setting on this grinder for a size on the shared scale, snapped to the grinder's steps. */
    fun value(microns: Double, spec: GrinderSpec): Double? {
        if (!canConvert(spec)) return null
        val steps = (microns - REFERENCE_MICRONS) / spec.micronsPerStep!!
        val raw = spec.defaultGrind!! + (if (spec.finerIsLower) steps else -steps) * spec.step
        return maxOf(0.0, roundHalfAway(raw / spec.step) * spec.step)
    }

    fun convert(value: Double, from: GrinderSpec, to: GrinderSpec): Double? = microns(value, from)?.let { value(it, to) }

    private val rangePattern = Regex("""(\d{3,4})\s*(?:[–—-]|to)\s*(\d{3,4})\s*(?:µm|μm|um|microns)|(\d{3,4})\s*(?:µm|μm|um|microns)""", RegexOption.IGNORE_CASE)

    /** The grind size range in a recipe's grind text, e.g. "Medium-fine (about 600–750 µm)" → 600..750. */
    fun micronRange(text: String): ClosedFloatingPointRange<Double>? {
        val match = rangePattern.find(text) ?: return null
        val low = match.groups[1]?.value?.toDoubleOrNull()
        val high = match.groups[2]?.value?.toDoubleOrNull()
        if (low != null && high != null) return minOf(low, high)..maxOf(low, high)
        val single = match.groups[3]?.value?.toDoubleOrNull() ?: return null
        return single..single
    }

    /** The recipe's grind size on this grinder, e.g. "≈ 22–25 clicks". Null when the grinder isn't calibrated. */
    fun hint(recipeGrind: String, spec: GrinderSpec): String? {
        val range = micronRange(recipeGrind) ?: return null
        val a = value(range.start, spec) ?: return null
        val b = value(range.endInclusive, spec) ?: return null
        val low = minOf(a, b)
        val high = maxOf(a, b)
        if (low == high) return "≈ " + spec.format(low)
        val lowText = spec.format(low).replace(" " + spec.unit.suffix, "")
        return "≈ $lowText–${spec.format(high)}"
    }
}

