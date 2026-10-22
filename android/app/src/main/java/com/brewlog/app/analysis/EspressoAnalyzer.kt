package com.brewlog.app.analysis

import com.brewlog.app.domain.MachineSample
import com.brewlog.app.domain.TasteFeedback
import com.brewlog.app.domain.WeightSample
import com.brewlog.app.domain.fmt1
import com.brewlog.app.domain.formatDate
import com.brewlog.app.domain.grams
import com.brewlog.app.domain.mmss
import com.brewlog.app.domain.roundHalfAway
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

// Port of EspressoAnalyzer.swift (rule-based, no AI) — keep keys, thresholds and priorities identical.
//  • Shot time is mostly grind: fast + sour → grind finer, slow + bitter → grind coarser.
//  • At a good shot time the ratio does the fine-tuning: sour → let it run longer, bitter → stop earlier.
//  • Temperature is the third lever: hotter for sour or light roasts, cooler for bitter or dark roasts.
//  • Sour and bitter together, very early first drops or a sudden pressure drop → channeling → puck prep.
//  • Weak / strong is the ratio or the dose.

object EspressoAnalyzer {
    const val TIME_TOLERANCE = 3.0
    const val RATIO_TOLERANCE = 0.2

    /** Time of the first gram in the cup. */
    fun firstDrops(samples: List<WeightSample>): Double? = samples.firstOrNull { it.w >= 1 }?.t

    data class PressureSummary(
        val peak: Double,
        /** Largest fall within 2 s while the pump was still pushing (not the ramp-down at the end). */
        val suddenDrop: Double,
        val dropTime: Double?,
        val averageTemperature: Double?,
    )

    fun pressureSummary(machine: List<MachineSample>): PressureSummary? {
        if (machine.size < 4) return null
        val peakSample = machine.reduce { a, b -> if (b.p > a.p) b else a }
        if (peakSample.p < 1) return null
        val end = machine.last().t
        val window = machine.filter { it.t >= peakSample.t && it.t <= end - 3 }
        var drop = 0.0
        var dropTime: Double? = null
        window.forEachIndexed { i, sample ->
            for (later in window.drop(i + 1)) {
                if (later.t - sample.t > 2) break
                if (sample.p - later.p > drop) {
                    drop = sample.p - later.p
                    dropTime = later.t
                }
            }
        }
        val temps = machine.mapNotNull { it.c }
        return PressureSummary(peakSample.p, drop, dropTime, if (temps.isEmpty()) null else temps.average())
    }

    fun analyze(input: AnalysisInput): BrewAnalysis {
        val recipe = input.recipe
        val feedback = input.feedback
        val hasCurve = input.usedScale && input.samples.size > 5
        val ratio = if (input.dose > 0) input.finalWeight / input.dose else 0.0
        val targetRatio = recipe.ratio
        val timeDelta = input.totalTime - recipe.targetTime
        val timeShort = timeDelta < -TIME_TOLERANCE
        val timeLong = timeDelta > TIME_TOLERANCE
        val timeVeryOff = abs(timeDelta) > 8
        val ratioLow = ratio > 0 && ratio < targetRatio - RATIO_TOLERANCE
        val ratioHigh = ratio > targetRatio + RATIO_TOLERANCE
        val drops = if (hasCurve) firstDrops(input.samples) else null
        val cupFlow = drops?.let { start -> if (input.totalTime - start > 3) input.finalWeight / (input.totalTime - start) else null }
        val pressure = pressureSummary(input.machine)
        val targetPressure = recipe.pressure ?: 9.0
        val pressureLow = pressure != null && pressure.peak < targetPressure - 2
        val channelSign = (pressure != null && pressure.suddenDrop >= 2) || (drops != null && drops < 3)
        val roastIndex = input.roastLevel?.ordinal
        val temp = input.waterTemp

        // Findings
        val findings = mutableListOf<Finding>()
        when {
            !timeShort && !timeLong -> findings += Finding(FindingLevel.GOOD, "Shot time ${input.totalTime.mmss()}",
                "Right on the ${recipe.targetTime.mmss()} target (±${TIME_TOLERANCE.toInt()} s).")
            timeShort -> findings += Finding(FindingLevel.WARNING, "Fast shot: ${input.totalTime.mmss()}",
                "${(-timeDelta).toInt()} s faster than the ${recipe.targetTime.mmss()} target. Usually the grind is too coarse or the dose too low.")
            else -> findings += Finding(FindingLevel.WARNING, "Slow shot: ${input.totalTime.mmss()}",
                "${timeDelta.toInt()} s slower than the ${recipe.targetTime.mmss()} target. Usually the grind is too fine or the dose too high.")
        }
        if (ratio > 0) {
            val text = "1:" + fmt1(ratio)
            findings += if (ratioLow || ratioHigh) {
                Finding(FindingLevel.INFO, "Ratio $text, planned ${recipe.ratioText}", "${input.finalWeight.grams()} in the cup instead of ${recipe.water.grams()}.")
            } else {
                Finding(FindingLevel.GOOD, "Ratio $text", "${input.finalWeight.grams()} from ${fmt1(input.dose)} g, as planned.")
            }
        }
        if (drops != null) {
            findings += when {
                drops < 3 -> Finding(FindingLevel.WARNING, "Early first drops (${drops.mmss()})",
                    "Coffee came through almost at once. That points to a coarse grind or a channel through the puck.")
                drops > 12 -> Finding(FindingLevel.INFO, "Late first drops (${drops.mmss()})", "A fine grind or a long pre-infusion. Fine if the taste is right.")
                else -> Finding(FindingLevel.GOOD, "First drops at ${drops.mmss()}", "A normal start for a shot.")
            }
        }
        if (cupFlow != null) {
            findings += Finding(if (cupFlow >= recipe.flowMin && cupFlow <= recipe.flowMax) FindingLevel.GOOD else FindingLevel.INFO,
                "Flow ${fmt1(cupFlow)} g/s", "Average in the cup after the first drops. Recipe: ${fmt1(recipe.flowMin)}–${fmt1(recipe.flowMax)} g/s.")
        }
        if (pressure != null) {
            findings += if (pressureLow) {
                Finding(FindingLevel.WARNING, "Low pressure: ${fmt1(pressure.peak)} bar",
                    "The recipe expects about ${roundHalfAway(targetPressure).toInt()} bar. The puck gave little resistance: grind finer or dose a little more.")
            } else {
                Finding(FindingLevel.GOOD, "Peak pressure ${fmt1(pressure.peak)} bar", "Recipe: about ${roundHalfAway(targetPressure).toInt()} bar.")
            }
            val dropTime = pressure.dropTime
            if (pressure.suddenDrop >= 2 && dropTime != null) {
                findings += Finding(FindingLevel.WARNING, "Pressure fell ${fmt1(pressure.suddenDrop)} bar at ${dropTime.mmss()}",
                    "A sudden drop during the shot usually means a channel opened in the puck.")
            }
            val avg = pressure.averageTemperature
            if (avg != null && abs(avg - temp) > 2) {
                findings += Finding(FindingLevel.INFO, "Brew temperature ${fmt1(avg)} °C",
                    "Planned ${temp.toInt()} °C. Let the machine heat up fully and flush before the shot.")
            }
        }
        input.daysOffRoast?.let { days ->
            if (days < 4) findings += Finding(FindingLevel.INFO, "Very fresh beans ($days d)",
                "Lots of CO₂ makes shots gush and channel. Espresso usually tastes best 7–21 days off roast.")
            else if (days > 40) findings += Finding(FindingLevel.INFO, "Older beans ($days d)",
                "Flavour fades and shots run faster. Grind finer to compensate, or use fresher beans.")
        }

        // Lean
        val sour = TasteFeedback.SOUR in feedback
        val bitter = TasteFeedback.BITTER in feedback || TasteFeedback.ASTRINGENT in feedback
        val lean = when {
            (sour && bitter) || (channelSign && !timeLong) -> ExtractionLean.UNEVEN
            timeShort || pressureLow -> ExtractionLean.UNDER
            timeLong -> ExtractionLean.OVER
            sour -> ExtractionLean.UNDER
            bitter -> ExtractionLean.OVER
            else -> ExtractionLean.BALANCED
        }

        // Suggestions
        val suggestions = LinkedHashMap<String, Suggestion>()
        fun add(key: String, title: String, detail: String, priority: Int, evidence: List<String> = emptyList(), grind: Double? = null) {
            val existing = suggestions[key]
            if (existing != null && existing.priority >= priority) {
                suggestions[key] = existing.copy(evidence = existing.evidence + evidence.filter { it !in existing.evidence })
                return
            }
            suggestions[key] = Suggestion(key, title, detail, priority, evidence, grind)
        }
        val timeEvidence = if (timeLong) {
            "Shot took ${input.totalTime.mmss()}, ${timeDelta.toInt()} s longer than planned"
        } else {
            "Shot took ${input.totalTime.mmss()}, ${(-timeDelta).toInt()} s faster than planned"
        }
        fun grindSuggestion(coarser: Boolean, priority: Int, evidence: List<String>) {
            val direction = if (coarser) "coarser" else "finer"
            val why = if (coarser) "A coarser grind lets the water through faster, so the shot runs quicker and less bitter."
            else "A finer grind slows the shot down and extracts more sweetness, so it tastes less sour."
            val grinder = input.grinder
            val value = grinder?.currentValue
            when {
                grinder != null && value != null -> {
                    val target = BrewAnalyzer.bracketed(coarser, value, grinder, input.history)
                        ?: grinder.spec.adjusted(value, coarser, if (timeVeryOff) 2.0 else 1.0)
                    add("grind", "Grind $direction: ${grinder.spec.format(target)}",
                        "Go from ${grinder.spec.format(value)} to ${grinder.spec.format(target)} on your ${grinder.name}. $why", priority, evidence, target)
                }
                grinder != null -> add("grind", "Grind $direction",
                    "Adjust your ${grinder.name} a small step $direction. Log the setting next time for exact numbers. $why", priority, evidence)
                else -> add("grind", "Grind $direction", "Make a small step $direction. $why Add your grinder in Gear to get exact recommendations.", priority, evidence)
            }
        }
        fun yieldText(r: Double) = "1:${fmt1(r)} (${roundHalfAway(input.dose * r).toInt()} g)"
        val ratioEvidence = listOf("Ratio 1:" + fmt1(ratio))

        val channelEvidence = mutableListOf<String>()
        val dropTime = pressure?.dropTime
        if (pressure != null && pressure.suddenDrop >= 2 && dropTime != null) channelEvidence += "Pressure fell ${fmt1(pressure.suddenDrop)} bar at ${dropTime.mmss()}"
        if (drops != null && drops < 3) channelEvidence += "First drops after ${drops.mmss()}"
        if (lean == ExtractionLean.UNEVEN || TasteFeedback.ASTRINGENT in feedback) {
            add("puck", "Improve the puck prep",
                "Break up clumps with a WDT tool, level the bed and tamp straight. A channel lets water rush through one spot: that part over-extracts (bitter, drying) while the rest stays sour.",
                110, channelEvidence)
        }
        if (sour) {
            when {
                timeShort || pressureLow -> grindSuggestion(false, 100,
                    if (timeShort) listOf(timeEvidence) else pressure?.let { listOf("Peak pressure only ${fmt1(it.peak)} bar") } ?: emptyList())
                ratioLow -> add("ratio", "Let it run to ${recipe.water.grams()}",
                    "You stopped at ${input.finalWeight.grams()}. A longer shot extracts more sweetness and balances the acidity.", 95, ratioEvidence)
                else -> add("ratio", "Longer ratio: ${yieldText(max(ratio, targetRatio) + 0.3)}",
                    "The shot time was fine, so let it run a few grams longer instead of changing the grind.", 85)
            }
            if (temp < 96) {
                add("temp-up", "Brew 1–2 °C hotter",
                    "Try ${temp.toInt() + 1}–${temp.toInt() + 2} °C. ${if (roastIndex != null && roastIndex <= 1) "Light roasts need the heat." else "Hotter water extracts more sweetness."}",
                    75, listOf("Brewed at ${temp.toInt()} °C"))
            }
        }
        if (bitter) {
            when {
                timeLong -> grindSuggestion(true, 100, listOf(timeEvidence))
                ratioHigh -> add("ratio", "Stop at ${recipe.water.grams()}",
                    "You let it run to ${input.finalWeight.grams()}. The last grams of a shot are the most bitter.", 95, ratioEvidence)
                else -> add("ratio", "Shorter ratio: ${yieldText(max(min(ratio, targetRatio) - 0.3, 1.0))}",
                    "The shot time was fine, so stop a few grams earlier instead of changing the grind.", 85)
            }
            add("temp-down", "Brew 1–2 °C cooler",
                "Try ${temp.toInt() - 2}–${temp.toInt() - 1} °C. ${if (roastIndex != null && roastIndex >= 3) "Darker roasts extract easily and turn bitter when hot." else "Cooler water extracts less of the harsh compounds."}",
                75, listOf("Brewed at ${temp.toInt()} °C"))
        }
        if (TasteFeedback.WEAK in feedback) {
            if (ratioHigh) add("strength", "Stop at ${recipe.water.grams()}", "More water in the cup means a thinner shot. Stick to the recipe's yield.", 90, ratioEvidence)
            else add("strength", "Dose 1 g more (${fmt1(input.dose + 1)} g)",
                "Keep the ratio and use a little more coffee for a stronger, heavier shot. Grind a touch coarser if it then runs slow.", 90)
        }
        if (TasteFeedback.STRONG in feedback) {
            add("strength", "Longer ratio: ${yieldText(max(ratio, targetRatio) + 0.3)}",
                "A few more grams in the cup make the shot less intense without changing the grind.", 90)
        }
        if (TasteFeedback.FLAT in feedback) {
            val days = input.daysOffRoast
            if (days != null && days > 30) {
                add("fresh", "Use fresher beans", "At $days days off roast most of the aroma is gone. Espresso is best 7–21 days off roast.", 85, listOf("$days days off roast"))
            }
            add("temp-up", "Brew 1–2 °C hotter", "A little more heat brings back sweetness and aroma.", 70)
        }
        // Without a taste yet, the shot time alone already says which way to go.
        if (feedback.isEmpty()) {
            if (timeShort) grindSuggestion(false, 60, listOf(timeEvidence))
            if (timeLong) grindSuggestion(true, 60, listOf(timeEvidence))
        }
        val negative = feedback.isNotEmpty() && TasteFeedback.PERFECT !in feedback
        val grinderContext = input.grinder
        if (negative && grinderContext != null) {
            val best = input.history.filter { it.grindValue != null && (it.rating >= 4 || TasteFeedback.PERFECT in it.feedback) }.maxByOrNull { it.rating }
            val bestGrind = best?.grindValue
            if (best != null && bestGrind != null && bestGrind != grinderContext.currentValue) {
                add("history", "Your best shot of this bean: ${grinderContext.spec.format(bestGrind)}",
                    "On ${formatDate(best.date)} it was rated ${best.rating}★ at ${grinderContext.spec.format(bestGrind)} (${best.totalTime.mmss()}).", 66)
            }
        }
        if (TasteFeedback.PERFECT in feedback) {
            suggestions.clear()
            val grindText = grinderContext?.currentValue?.let { " at ${grinderContext.spec.format(it)}" } ?: ""
            add("repeat", "Repeat it", "This shot is saved as your reference$grindText. BrewLog will suggest the same settings next time you use this bean.", 100)
        }

        val sorted = suggestions.values.sortedByDescending { it.priority }
        val suggestedGrind = if (TasteFeedback.PERFECT in feedback) input.grinder?.currentValue else sorted.firstOrNull { it.grindTarget != null }?.grindTarget

        val headline = when {
            feedback.isEmpty() -> when (lean) {
                ExtractionLean.BALANCED -> "The shot went to plan. Now taste it and tell BrewLog how it was."
                ExtractionLean.UNDER -> "The shot ran fast: watch for sourness."
                ExtractionLean.OVER -> "The shot ran slow: watch for bitterness."
                ExtractionLean.UNEVEN -> "The data hints at channeling. Taste it and tell BrewLog how it was."
                ExtractionLean.UNKNOWN -> "Taste it and tell BrewLog how it was to get tailored tips."
            }
            TasteFeedback.PERFECT in feedback -> "Nailed it. These settings are your reference for this coffee."
            lean == ExtractionLean.UNEVEN -> "Sour and bitter together points to channeling. Start with the puck prep."
            sour && timeShort -> "Under-extracted: the fast shot explains the sourness."
            bitter && timeLong -> "Over-extracted: the slow shot explains the bitterness."
            else -> "Here's what to change next time, most impactful first."
        }

        val metrics = BrewMetrics(timeDelta, TIME_TOLERANCE, null, null, cupFlow, null, null, null, ratio)
        return BrewAnalysis(
            pours = emptyList(), metrics = metrics,
            findings = findings.withIndex().sortedWith(compareByDescending<IndexedValue<Finding>> { it.value.level.ordinal }.thenBy { it.index }).map { it.value },
            suggestions = sorted, lean = lean, headline = headline, suggestedGrind = suggestedGrind,
        )
    }
}
