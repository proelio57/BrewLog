package com.brewlog.app.analysis

import com.brewlog.app.domain.FilterFlow
import com.brewlog.app.domain.GrinderSpec
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.RecipeStep
import com.brewlog.app.domain.RoastLevel
import com.brewlog.app.domain.StepKind
import com.brewlog.app.domain.TasteFeedback
import com.brewlog.app.domain.ValveState
import com.brewlog.app.domain.WeightSample
import com.brewlog.app.domain.fmt1
import com.brewlog.app.domain.formatDate
import com.brewlog.app.domain.mmss
import com.brewlog.app.domain.roundHalfAway
import kotlin.math.abs
import kotlin.math.max

// Rule-based (no AI) brew analysis. 1:1 port of BrewAnalyzer.swift — keep keys, thresholds and priorities identical.
//
//  • Under-extraction → sour, salty, thin. Causes: coarse grind, cool water, short contact time, little agitation,
//    small/short bloom, very fresh beans (CO₂), fast filter paper.
//  • Over-extraction → bitter, harsh, dry. Causes: fine grind, hot water (esp. dark roasts), long contact time /
//    slow drawdown (fines, clogging, slow paper), excessive agitation.
//  • Uneven extraction (channeling) → sour AND bitter/astringent at the same time.
//  • Strength (weak/strong) is mostly brew ratio; extraction (sour/bitter) is grind, temperature and time.

data class GrinderContext(val name: String, val spec: GrinderSpec, val currentValue: Double?)

/** A previous brew of the same bean (and grinder), used to bracket the grind setting. */
data class PastBrew(
    val date: Long,
    val recipeId: String,
    val grindValue: Double?,
    val rating: Int,
    val feedback: Set<TasteFeedback>,
    val totalTime: Double,
)

data class AnalysisInput(
    val recipe: Recipe,
    val samples: List<WeightSample>,
    val usedScale: Boolean,
    val totalTime: Double,
    val finalWeight: Double,
    val dose: Double,
    val waterTemp: Double,
    val roastLevel: RoastLevel?,
    val daysOffRoast: Int?,
    val filterName: String,
    val filterFlow: FilterFlow?,
    val filterIdealRoast: RoastLevel?,
    val grinder: GrinderContext?,
    val feedback: Set<TasteFeedback>,
    /** Earlier brews with the same bean and grinder, newest first (excluding the analysed brew). */
    val history: List<PastBrew>,
    /** Espresso: pressure, temperature and flow from the machine or pressure sensor. */
    val machine: List<com.brewlog.app.domain.MachineSample> = emptyList(),
)

enum class FindingLevel { GOOD, INFO, WARNING }

data class Finding(val level: FindingLevel, val title: String, val detail: String)

data class Suggestion(
    val key: String,
    val title: String,
    val detail: String,
    val priority: Int,
    /** What in the brew data triggered this suggestion (empty = general advice). */
    val evidence: List<String>,
    val grindTarget: Double?,
)

data class PourResult(
    val number: Int,
    val stepIndex: Int,
    val step: RecipeStep,
    val target: Double,
    val actualStart: Double? = null,
    val actualEnd: Double? = null,
    val reached: Double? = null,
    val averageFlow: Double? = null,
) {
    val startDelta: Double? get() = actualStart?.let { it - step.time }
    val weightDelta: Double? get() = reached?.let { it - target }
    val detected: Boolean get() = actualStart != null
}

data class BrewMetrics(
    val timeDelta: Double,
    val timeTolerance: Double,
    val drawdown: Double?,
    val expectedDrawdown: Double?,
    val averageFlow: Double?,
    val peakFlow: Double?,
    val bloomRatio: Double?,
    val bloomDuration: Double?,
    val ratio: Double,
)

enum class ExtractionLean(val title: String) {
    UNDER("Leaning under-extracted"),
    BALANCED("Balanced extraction"),
    OVER("Leaning over-extracted"),
    UNEVEN("Uneven extraction"),
    UNKNOWN("Mixed signals"),
}

data class BrewAnalysis(
    val pours: List<PourResult>,
    val metrics: BrewMetrics,
    val findings: List<Finding>,
    val suggestions: List<Suggestion>,
    val lean: ExtractionLean,
    val headline: String,
    /** Grind to use next time (pre-filled in the brew setup for this bean and grinder). */
    val suggestedGrind: Double?,
)

object BrewAnalyzer {

    // MARK: - Pour detection

    data class Segment(val start: Double, val end: Double, val startWeight: Double, val endWeight: Double) {
        val duration: Double get() = max(end - start, 0.1)
        val poured: Double get() = endWeight - startWeight
    }

    /** Smoothed flow (g/s) for each sample using a ~1 s backward window (used for analysis). */
    fun flows(samples: List<WeightSample>): List<Double> {
        val result = ArrayList<Double>(samples.size)
        var j = 0
        for (i in samples.indices) {
            while (j < i && samples[i].t - samples[j].t > 1.0) j++
            val dt = samples[i].t - samples[j].t
            result.add(if (dt > 0.3) (samples[i].w - samples[j].w) / dt else 0.0)
        }
        return result
    }

    /** Flow (g/s) centred on each sample (±half the window). Lines up with the weight curve, so used for charts. */
    fun centeredFlows(samples: List<WeightSample>, window: Double = 1.0): List<Double> {
        if (samples.size <= 1) return List(samples.size) { 0.0 }
        val half = window / 2
        val result = DoubleArray(samples.size)
        var lo = 0
        var hi = 0
        for (i in samples.indices) {
            val t = samples[i].t
            while (lo < i && samples[lo].t < t - half) lo++
            if (hi < i) hi = i
            while (hi + 1 < samples.size && samples[hi + 1].t <= t + half) hi++
            val dt = samples[hi].t - samples[lo].t
            result[i] = if (dt >= 0.3) (samples[hi].w - samples[lo].w) / dt else 0.0
        }
        return result.toList()
    }

    /** Splits the weight curve into pour segments (periods where weight rises). */
    fun detectSegments(samples: List<WeightSample>): List<Segment> {
        if (samples.size <= 5) return emptyList()
        val flow = flows(samples)
        val raw = mutableListOf<Pair<Int, Int>>()
        var inPour = false
        var startIndex = 0
        var lowSince: Int? = null

        for (i in samples.indices) {
            if (!inPour) {
                if (flow[i] > 1.0) {
                    inPour = true
                    lowSince = null
                    // Walk back to where the weight actually started rising.
                    var k = i
                    val windowStart = samples.indexOfLast { it.t <= samples[i].t - 1.0 }.let { if (it < 0) 0 else it }
                    val base = samples[windowStart].w
                    while (k > windowStart && samples[k - 1].w > base + 0.3) k--
                    startIndex = max(k - 1, 0)
                }
            } else if (flow[i] < 0.4) {
                val low = lowSince ?: i
                lowSince = low
                if (samples[i].t - samples[low].t >= 0.8) {
                    raw.add(startIndex to i)
                    inPour = false
                    lowSince = null
                }
            } else {
                lowSince = null
            }
        }
        if (inPour) raw.add(startIndex to samples.size - 1)

        val segments = raw.map { (from, to) ->
            var peak = Double.NEGATIVE_INFINITY
            for (index in from..to) peak = max(peak, samples[index].w)
            var endIndex = to
            for (index in from..to) {
                if (samples[index].w >= peak - 0.3) {
                    endIndex = index
                    break
                }
            }
            Segment(samples[from].t, samples[endIndex].t, samples[from].w, peak)
        }

        // Merge segments separated by tiny pauses.
        val merged = mutableListOf<Segment>()
        for (segment in segments) {
            val last = merged.lastOrNull()
            if (last != null && segment.start - last.end < 1.5) {
                merged[merged.size - 1] = last.copy(end = segment.end, endWeight = max(last.endWeight, segment.endWeight))
            } else {
                merged.add(segment)
            }
        }
        return merged.filter { it.poured >= 2 }
    }

    /** Splits continuous pours that run through an intermediate target (e.g. pouring 0:45→1:45 without pausing). */
    fun splitAtTargets(segments: List<Segment>, samples: List<WeightSample>, recipe: Recipe): List<Segment> {
        val pours = recipe.pourSteps
        if (pours.size <= 1) return segments
        val result = mutableListOf<Segment>()
        for (segment in segments) {
            var current = segment
            for (offset in 0 until pours.size - 1) {
                val target = pours[offset].target ?: continue
                val nextTime = pours[offset + 1].time
                if (current.startWeight >= target - 5 || current.endWeight <= target + 5) continue
                if (nextTime <= current.start - 10 || nextTime >= current.end + 10) continue
                val crossing = samples.firstOrNull { it.t >= current.start && it.w >= target } ?: continue
                result.add(Segment(current.start, crossing.t, current.startWeight, crossing.w))
                current = Segment(crossing.t, current.end, crossing.w, current.endWeight)
            }
            result.add(current)
        }
        return result.filter { it.poured >= 2 }
    }

    fun matchPours(recipe: Recipe, segments: List<Segment>): List<PourResult> {
        val pourIndices = recipe.steps.indices.filter { recipe.steps[it].kind.isPour && recipe.steps[it].target != null }
        val assigned = mutableMapOf<Int, MutableList<Segment>>()
        var minPosition = 0
        for (segment in segments) {
            if (minPosition >= pourIndices.size) break
            var best = minPosition
            var bestDistance = Double.POSITIVE_INFINITY
            for (position in minPosition until pourIndices.size) {
                val distance = abs(segment.start - recipe.steps[pourIndices[position]].time)
                if (distance < bestDistance) {
                    bestDistance = distance
                    best = position
                }
            }
            assigned.getOrPut(pourIndices[best]) { mutableListOf() }.add(segment)
            minPosition = best
        }

        var pourCounter = 0
        return pourIndices.map { index ->
            val step = recipe.steps[index]
            // The bloom is "B"; pours after it are numbered 1, 2, 3…
            val number = if (step.kind == StepKind.BLOOM) 0 else ++pourCounter
            val base = PourResult(number, index, step, step.target ?: 0.0)
            val segs = assigned[index]
            if (segs.isNullOrEmpty()) {
                base
            } else {
                val first = segs.first()
                val last = segs.last()
                val pouredTime = segs.sumOf { it.duration }
                base.copy(
                    actualStart = first.start,
                    actualEnd = last.end,
                    reached = last.endWeight,
                    averageFlow = (last.endWeight - first.startWeight) / max(pouredTime, 0.5),
                )
            }
        }
    }

    // MARK: - Main analysis

    fun analyze(input: AnalysisInput): BrewAnalysis {
        if (input.recipe.isEspresso) return EspressoAnalyzer.analyze(input)
        val recipe = input.recipe
        val samples = input.samples
        val hasCurve = input.usedScale && samples.size > 10

        var segments: List<Segment> = emptyList()
        var pours: List<PourResult> = emptyList()
        if (hasCurve) {
            segments = splitAtTargets(detectSegments(samples), samples, recipe)
            pours = matchPours(recipe, segments)
        }

        // Metrics
        val tolerance = max(15.0, recipe.targetTime * 0.08)
        val timeDelta = input.totalTime - recipe.targetTime
        val ratio = if (input.dose > 0) input.finalWeight / input.dose else 0.0

        val totalPoured = segments.sumOf { it.poured }
        val totalPourTime = segments.sumOf { it.duration }
        val averageFlow: Double? = if (totalPourTime > 2) totalPoured / totalPourTime else null
        val peakFlow: Double? = if (hasCurve) flows(samples).maxOrNull() else null

        val valveRecipe = recipe.steps.any { it.kind == StepKind.OPEN_VALVE || it.valve == ValveState.CLOSED }
        var drawdown: Double? = null
        var expectedDrawdown: Double? = null
        // Finish was tapped (almost) right after the last pour, so the total time doesn't include the drawdown.
        var drawdownMissing = false
        val lastSegment = segments.lastOrNull()
        if (valveRecipe) {
            val open = recipe.steps.lastOrNull { it.kind == StepKind.OPEN_VALVE }
            if (open != null) {
                drawdown = input.totalTime - open.time
                expectedDrawdown = recipe.targetTime - open.time
            }
        } else if (lastSegment != null && input.totalTime - lastSegment.end < 5) {
            drawdownMissing = true
        } else if (lastSegment != null) {
            drawdown = input.totalTime - lastSegment.end
            val planned = recipe.pourSteps
            val last = planned.lastOrNull()
            val lastTarget = last?.target
            if (last != null && lastTarget != null) {
                val previousTarget = if (planned.size > 1) planned[planned.size - 2].target ?: 0.0 else 0.0
                val idealFlow = max((recipe.flowMin + recipe.flowMax) / 2, 1.0)
                expectedDrawdown = max(recipe.targetTime - (last.time + (lastTarget - previousTarget) / idealFlow), 20.0)
            }
        }

        val bloomStep = recipe.steps.firstOrNull { it.kind == StepKind.BLOOM }
        var bloomRatio: Double? = null
        var bloomDuration: Double? = null
        val plannedBloom = bloomStep?.target
        if (plannedBloom != null && input.dose > 0) {
            val actual = pours.firstOrNull()?.reached ?: plannedBloom
            bloomRatio = actual / input.dose
            if (pours.size > 1) {
                bloomDuration = pours[1].actualStart ?: pours[1].step.time
            } else if (recipe.pourSteps.size > 1) {
                bloomDuration = recipe.pourSteps[1].time
            }
        }

        val metrics = BrewMetrics(timeDelta, tolerance, drawdown, expectedDrawdown, averageFlow, peakFlow, bloomRatio, bloomDuration, ratio)
        val drawdownValue = drawdown
        val expectedDrawdownValue = expectedDrawdown
        val bloomRatioValue = bloomRatio
        val bloomDurationValue = bloomDuration

        // Signals (total time is only trusted when the drawdown was recorded)
        val timeLong = !drawdownMissing && timeDelta > tolerance
        val timeShort = !drawdownMissing && timeDelta < -tolerance
        val timeVeryOff = !drawdownMissing && abs(timeDelta) > tolerance * 2
        val drawdownSlow = drawdownValue != null && expectedDrawdownValue != null && drawdownValue > expectedDrawdownValue + 25
        val drawdownFast = drawdownValue != null && expectedDrawdownValue != null && drawdownValue < expectedDrawdownValue - 25
        val flowFast = averageFlow?.let { it > recipe.flowMax * 1.15 } ?: false
        val flowSlow = averageFlow?.let { it < recipe.flowMin * 0.85 } ?: false
        val roastIndex = input.roastLevel?.index
        val tempLow = input.waterTemp > 0 &&
            (input.waterTemp < recipe.temperature - 2.5 || ((roastIndex ?: 2) <= 1 && input.waterTemp < 92))
        val tempHigh = input.waterTemp > 0 &&
            (input.waterTemp > recipe.temperature + 2.5 || ((roastIndex ?: 0) >= 3 && input.waterTemp > 93))
        val ratioLow = ratio > 0 && ratio < recipe.ratio - 0.7
        val ratioHigh = ratio > 0 && ratio > recipe.ratio + 0.7
        val bloomSmall = bloomRatioValue?.let { it < 1.8 } ?: false
        val bloomShort = bloomDurationValue?.let { it < 25 } ?: false
        val tooFresh = input.daysOffRoast?.let { it < 4 } ?: false
        val stale = input.daysOffRoast?.let { it > 45 } ?: false
        val filterSlowish = input.filterFlow == FilterFlow.SLOW || input.filterFlow == FilterFlow.MEDIUM
        val filterFast = input.filterFlow == FilterFlow.FAST

        val findings = buildFindings(
            input, recipe, pours, tolerance, timeDelta, timeLong, drawdownMissing, drawdownValue, expectedDrawdownValue,
            drawdownSlow, drawdownFast, bloomRatioValue, bloomSmall, bloomDurationValue, bloomShort, averageFlow, flowFast,
            flowSlow, ratio, roastIndex, tooFresh, stale,
        )

        // MARK: Extraction lean (data only)
        var overScore = 0.0
        var underScore = 0.0
        if (timeLong) overScore += 1
        if (timeShort) underScore += 1
        if (drawdownSlow) overScore += 0.5
        if (drawdownFast) underScore += 0.5
        if (tempHigh) overScore += 0.5
        if (tempLow) underScore += 0.5
        if (ratioHigh) overScore += 0.5
        if (ratioLow) underScore += 0.5
        if (bloomSmall || bloomShort) underScore += 0.3
        if (flowFast) overScore += 0.3

        var lean = when {
            overScore - underScore >= 1 -> ExtractionLean.OVER
            underScore - overScore >= 1 -> ExtractionLean.UNDER
            overScore < 0.5 && underScore < 0.5 -> ExtractionLean.BALANCED
            else -> ExtractionLean.UNKNOWN
        }

        val feedback = input.feedback
        val sour = TasteFeedback.SOUR in feedback
        val bitter = TasteFeedback.BITTER in feedback
        val astringent = TasteFeedback.ASTRINGENT in feedback
        if (sour && (bitter || astringent)) lean = ExtractionLean.UNEVEN

        // MARK: Suggestions
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
            "Brew took ${input.totalTime.mmss()}, ${timeDelta.toInt()} s longer than planned"
        } else {
            "Brew took ${input.totalTime.mmss()}, ${(-timeDelta).toInt()} s faster than planned"
        }
        val avgFlowText = fmt1(averageFlow ?: 0.0)

        fun grindSuggestion(coarser: Boolean, priority: Int, evidence: List<String>) {
            val direction = if (coarser) "coarser" else "finer"
            val multiplier = if (timeVeryOff) 2.0 else 1.0
            val why = if (coarser) {
                "A coarser grind slows extraction and speeds up drawdown, which reduces bitterness and harshness."
            } else {
                "A finer grind exposes more surface and slows the flow, so more sweetness and less sourness."
            }
            val grinder = input.grinder
            val value = grinder?.currentValue
            when {
                grinder != null && value != null -> {
                    val target = bracketed(coarser, value, grinder, input.history)
                        ?: grinder.spec.adjusted(value, coarser, multiplier)
                    add("grind", "Grind $direction: ${grinder.spec.format(target)}",
                        "Go from ${grinder.spec.format(value)} to ${grinder.spec.format(target)} on your ${grinder.name}. $why",
                        priority, evidence, target)
                }
                grinder != null -> add("grind", "Grind $direction",
                    "Adjust your ${grinder.name} about ${grinder.spec.formatDelta(grinder.spec.adjustStep * multiplier)} $direction. " +
                        "Log the setting next time for exact numbers. $why",
                    priority, evidence)
                else -> add("grind", "Grind $direction",
                    "Make a small step $direction. $why Add your grinder in Gear to get exact click recommendations.",
                    priority, evidence)
            }
        }

        val isFourSix = recipe.id.startsWith("kasuya-46")
        val isImmersion = recipe.steps.any { it.valve == ValveState.CLOSED }

        if (lean == ExtractionLean.UNEVEN) {
            add("evenness", "Even out the extraction",
                "Sour and bitter together usually means channeling: some grounds over-extract while water rushes past others. " +
                    "Pour gently in the centre, avoid hitting the paper walls, and swirl after the bloom and the last pour to flatten the bed.",
                110, if (flowFast) listOf("Average pour rate $avgFlowText g/s is above the recipe range") else emptyList())
            add("fines", "Reduce fines",
                "Lots of fines clog the paper and channel. Try a slightly coarser grind, or sift and remove the dust.", 70)
        }

        if (sour) {
            if (timeShort) {
                grindSuggestion(coarser = false, priority = 100, evidence = listOf(timeEvidence))
            } else if (timeLong) {
                add("evenness", "Even out the extraction",
                    "The brew was slow but still sour. That points to uneven extraction (channeling or a clogged bed), not a grind that's too coarse. " +
                        "Pour more gently and centrally, swirl to flatten the bed, and check for fines.",
                    95, listOf(timeEvidence))
            }
            if (tempLow) {
                add("temp-up", "Use hotter water",
                    "Try ${if ((roastIndex ?: 99) <= 1) "96–100" else "93–96"} °C. Hotter water dissolves more of the sugars and balances acidity.",
                    90, listOf("Water was ${input.waterTemp.toInt()} °C"))
            }
            if (bloomSmall || bloomShort) {
                add("bloom", "Bloom longer and bigger",
                    "Use 2–3× the dose in water for 40–45 s and swirl so no dry clumps remain.",
                    80, listOfNotNull(bloomRatioValue?.let { "Bloom was ${fmt1(it)}× dose" }, bloomDurationValue?.let { "Bloom lasted ${it.toInt()} s" }))
            }
            if (ratioLow) {
                add("ratio-up", "Use the full amount of water",
                    "A tighter ratio extracts less. Aim for ${recipe.ratioText}.", 70, listOf("Brewed at 1:${fmt1(ratio)}"))
            }
            if (flowSlow && !timeLong) {
                add("agitation-up", "Add a little agitation",
                    "Pour a bit faster or give the brewer a gentle swirl after the bloom and the last pour.",
                    60, listOf("Average pour rate $avgFlowText g/s"))
            }
            if (filterFast && (timeShort || drawdownFast)) {
                add("filter-slower", "Try a medium-flow paper",
                    "${input.filterName} drains fast. CAFEC T-90 or the Hario standard paper keep the coffee in contact longer.",
                    55, listOf("Fast drawdown with a fast paper"))
            }
            if (tooFresh) {
                add("rest", "Let the beans rest",
                    "Wait a few more days. Fresh beans release CO₂, which causes uneven extraction and sharp acidity.",
                    50, listOf("${input.daysOffRoast} days off roast"))
            }
            if (isFourSix) {
                add("46-sweet", "Shift the 4:6 balance toward sweetness",
                    "In 4:6 the first 40% controls the balance. Make the first pour smaller and the second larger (e.g. 50 g then 70 g).", 65)
            }
            if (lean != ExtractionLean.UNEVEN && !timeLong && "grind" !in suggestions) {
                grindSuggestion(coarser = false, priority = 75, evidence = emptyList())
            }
            if ("temp-up" !in suggestions && input.waterTemp > 0 && input.waterTemp < 99) {
                add("temp-up", "Raise the temperature 2–3 °C",
                    "A small temperature increase gives a little more extraction without changing anything else.", 58)
            }
        }

        if (bitter) {
            if (timeLong) {
                grindSuggestion(coarser = true, priority = 100, evidence = listOf(timeEvidence))
            } else if (timeShort) {
                add("evenness", "Even out the extraction",
                    "The brew was quick but still bitter. That usually means channeling, or the water is too hot for this roast. Pour more gently and centrally.",
                    85, listOf(timeEvidence))
            }
            if (drawdownSlow) {
                add("drawdown", "Speed up the drawdown",
                    "Swirl gently instead of stirring at the end, and avoid pouring onto the paper walls." +
                        if (filterSlowish) " A faster paper (CAFEC Abaca+, T-92, Hario tabbed or Sibarist FAST) also helps." else "",
                    80, listOf("Drawdown ${drawdownValue.mmss()} vs about ${expectedDrawdownValue.mmss()} expected"))
            }
            if (tempHigh) {
                add("temp-down", "Lower the water temperature",
                    "Try ${if ((roastIndex ?: -1) >= 3) "85–90" else "90–92"} °C. Darker roasts dissolve easily and turn harsh when the water is too hot.",
                    88, listOf("Water was ${input.waterTemp.toInt()} °C"))
            }
            if (flowFast) {
                add("gentle", "Pour more gently",
                    "Lower the kettle and slow the stream. Turbulent pours over-agitate the bed and pull out bitter compounds.",
                    75, listOf("Average pour rate $avgFlowText g/s"))
            }
            if (ratioHigh) {
                add("ratio-down", "Don't overshoot the water",
                    "Extra water keeps extracting the late, bitter compounds. Stop at ${recipe.water.toInt()} g.",
                    60, listOf("Brewed at 1:${fmt1(ratio)}"))
            }
            if (input.filterIdealRoast == RoastLevel.LIGHT && (roastIndex ?: 0) >= 3) {
                add("filter-roast", "Use a dark-roast paper",
                    "CAFEC T-83 (or T-90) suits darker roasts better and gives more body with less harshness.", 50)
            }
            if (stale) {
                add("fresh", "Use fresher beans",
                    "Old beans lose sweetness and aromatics, so bitterness stands out more.",
                    40, listOf("${input.daysOffRoast} days off roast"))
            }
            if ("grind" !in suggestions && !timeShort && lean != ExtractionLean.UNEVEN) {
                grindSuggestion(coarser = true, priority = 74, evidence = emptyList())
            }
            if ("temp-down" !in suggestions && input.waterTemp > 88) {
                add("temp-down", "Lower the temperature 2–3 °C",
                    "Slightly cooler water extracts a little less and softens bitterness.", 56)
            }
        }

        if (astringent && lean != ExtractionLean.UNEVEN) {
            if (flowFast) {
                add("gentle", "Pour more gently",
                    "Drying, rough cups are often caused by aggressive pours that channel. Lower the kettle and keep a thin, steady stream.",
                    95, listOf("Average pour rate $avgFlowText g/s"))
            }
            if (timeLong || drawdownSlow) {
                grindSuggestion(coarser = true, priority = 85, evidence = listOf(if (timeLong) timeEvidence else "Slow drawdown"))
                add("fines", "Reduce fines",
                    "Fines clog the paper and over-extract into astringency. Sift them out or try a slightly coarser grind.", 70)
            }
            add("walls", "Pour in the centre and flatten the bed",
                "Avoid pouring onto the paper walls (water bypasses the coffee), and finish with a gentle swirl.", 65)
            add("rinse", "Rinse the paper well",
                "Rinse with plenty of hot water to remove paper taste and preheat the brewer.", 40)
        }

        if (TasteFeedback.WEAK in feedback) {
            if (ratioHigh || (input.usedScale && input.finalWeight > recipe.water * 1.04)) {
                add("ratio-strength", "Stop at the target water",
                    "You used more water than planned, which dilutes the cup.", 92, listOf("Brewed at 1:${fmt1(ratio)}"))
            }
            if (timeShort) grindSuggestion(coarser = false, priority = 80, evidence = listOf(timeEvidence))
            add("dose-up", "Use a bit more coffee",
                "Strength mostly depends on the ratio. Try +1 g of coffee (about 1:${fmt1(max(recipe.ratio - 1, 12.0))}) with the same water.", 76)
            if (isFourSix) {
                add("46-strength", "Split the last 60% into more pours",
                    "In 4:6 the number of pours in the second phase sets strength. 3 → 4 pours makes it stronger.", 70)
            }
            if (isImmersion) add("steep-longer", "Steep longer", "Open the valve 20–30 s later for more strength and extraction.", 72)
        }

        if (TasteFeedback.STRONG in feedback) {
            if (ratioLow || (input.usedScale && input.finalWeight < recipe.water * 0.96)) {
                add("ratio-strength", "Use all of the water",
                    "You stopped short of the target water, so the cup is more concentrated.", 92, listOf("Brewed at 1:${fmt1(ratio)}"))
            }
            add("ratio-up-strength", "Use a longer ratio",
                "Try about 1:${fmt1(recipe.ratio + 1)}. Use the same coffee with more water, or 1 g less coffee.", 76)
            if (isFourSix) {
                add("46-strength", "Use fewer pours in the 60% phase", "Two larger pours instead of three gives a lighter cup.", 70)
            }
            if (isImmersion) add("steep-shorter", "Steep shorter", "Open the valve 20–30 s earlier.", 72)
        }

        if (TasteFeedback.FLAT in feedback) {
            if (stale) {
                add("fresh", "Use fresher beans",
                    "Flat, hollow cups are the classic sign of beans that are past their peak.",
                    95, listOf("${input.daysOffRoast} days off roast"))
            }
            if (tempLow) {
                add("temp-up", "Use hotter water", "More heat extracts more aromatics and sweetness.",
                    85, listOf("Water was ${input.waterTemp.toInt()} °C"))
            }
            if (timeShort) grindSuggestion(coarser = false, priority = 75, evidence = listOf(timeEvidence))
            add("water", "Check your water",
                "Distilled or very soft water tastes flat, and very hard water dulls acidity. Aim for about 50–100 ppm hardness " +
                    "(e.g. a light-roast mineral recipe or a low-mineral bottled water).", 60)
            add("clarity", "Try a recipe with more clarity",
                "Rao V60 or a fast paper like CAFEC T-92 or Abaca+ brings out brighter, more defined flavours.", 45)
        }

        // History hint: point to the best-rated brew of this bean
        val negative = feedback.isNotEmpty() && TasteFeedback.PERFECT !in feedback
        val grinderContext = input.grinder
        if (negative && grinderContext != null) {
            val best = input.history
                .filter { it.grindValue != null && (it.rating >= 4 || TasteFeedback.PERFECT in it.feedback) }
                .maxByOrNull { it.rating }
            val bestGrind = best?.grindValue
            if (best != null && bestGrind != null && bestGrind != grinderContext.currentValue) {
                add("history", "Your best brew of this bean: ${grinderContext.spec.format(bestGrind)}",
                    "On ${formatDate(best.date)} it was rated ${best.rating}★ at ${grinderContext.spec.format(bestGrind)} (${best.totalTime.mmss()}).", 66)
            }
        }

        if (TasteFeedback.PERFECT in feedback) {
            suggestions.clear()
            val grindText = grinderContext?.let { g -> g.currentValue?.let { " at ${g.spec.format(it)}" } } ?: ""
            add("repeat", "Repeat it",
                "This brew is saved as your reference$grindText. BrewLog will suggest the same settings next time you brew this bean.", 100)
        }

        val sorted = suggestions.values.sortedByDescending { it.priority }

        val suggestedGrind = if (TasteFeedback.PERFECT in feedback) {
            input.grinder?.currentValue
        } else {
            sorted.firstOrNull { it.grindTarget != null }?.grindTarget
        }

        val headline = when {
            feedback.isEmpty() -> when (lean) {
                ExtractionLean.BALANCED -> "Everything went to plan. Now taste it and tell BrewLog how it was."
                ExtractionLean.OVER -> "The data leans over-extracted: watch for bitterness."
                ExtractionLean.UNDER -> "The data leans under-extracted: watch for sourness."
                else -> "Taste it and tell BrewLog how it was to get tailored tips."
            }
            TasteFeedback.PERFECT in feedback -> "Nailed it. These settings are your reference for this coffee."
            lean == ExtractionLean.UNEVEN -> "Sour and bitter at the same time points to uneven extraction."
            sour && lean == ExtractionLean.UNDER -> "Under-extracted: the brew data agrees with the sourness."
            bitter && lean == ExtractionLean.OVER -> "Over-extracted: the brew data agrees with the bitterness."
            sour || bitter -> "Here's what to change next time, most impactful first."
            else -> "A few tweaks for next time."
        }

        return BrewAnalysis(
            pours = pours,
            metrics = metrics,
            findings = findings.sortedByDescending { it.level.ordinal },
            suggestions = sorted,
            lean = lean,
            headline = headline,
            suggestedGrind = suggestedGrind,
        )
    }

    private fun buildFindings(
        input: AnalysisInput, recipe: Recipe, pours: List<PourResult>, tolerance: Double, timeDelta: Double,
        timeLong: Boolean, drawdownMissing: Boolean, drawdown: Double?, expectedDrawdown: Double?,
        drawdownSlow: Boolean, drawdownFast: Boolean, bloomRatio: Double?, bloomSmall: Boolean,
        bloomDuration: Double?, bloomShort: Boolean, averageFlow: Double?, flowFast: Boolean, flowSlow: Boolean,
        ratio: Double, roastIndex: Int?, tooFresh: Boolean, stale: Boolean,
    ): List<Finding> {
        val findings = mutableListOf<Finding>()
        val planned = "${input.totalTime.mmss()} vs ${recipe.targetTime.mmss()} planned."

        when {
            drawdownMissing -> findings += Finding(FindingLevel.INFO, "Drawdown not recorded",
                "Finish was tapped right after the last pour. Tap Finish when the bed is dry so total time and drawdown can be analysed.")
            abs(timeDelta) <= tolerance -> findings += Finding(FindingLevel.GOOD, "Brew time on target", planned)
            else -> findings += Finding(FindingLevel.WARNING,
                if (timeLong) "Brew ran long (+${timeDelta.toInt()} s)" else "Brew finished fast (−${(-timeDelta).toInt()} s)",
                "$planned Contact time is one of the biggest extraction levers.")
        }

        if (drawdown != null && expectedDrawdown != null) {
            if (drawdownSlow) {
                findings += Finding(FindingLevel.WARNING, "Slow drawdown",
                    "${drawdown.mmss()} after the last pour (expected about ${expectedDrawdown.mmss()}). " +
                        "Usually caused by a fine grind, lots of fines, a slow paper or too much agitation at the end.")
            } else if (drawdownFast) {
                findings += Finding(FindingLevel.INFO, "Fast drawdown",
                    "${drawdown.mmss()} after the last pour (expected about ${expectedDrawdown.mmss()}). " +
                        "The water passed through quickly, so there was less contact time.")
            }
        }

        if (bloomRatio != null) {
            findings += if (bloomSmall) {
                Finding(FindingLevel.WARNING, "Small bloom (${fmt1(bloomRatio)}× dose)",
                    "Aim for 2–3× the coffee weight so that all grounds are wet and degas evenly.")
            } else {
                Finding(FindingLevel.GOOD, "Bloom ${fmt1(bloomRatio)}× dose", "Enough water to saturate the bed.")
            }
        }
        if (bloomDuration != null && bloomShort) {
            findings += Finding(FindingLevel.INFO, "Short bloom (${bloomDuration.toInt()} s)",
                "30–45 s gives CO₂ time to escape so water can extract evenly.")
        }

        for (pour in pours) {
            val label = if (pour.step.kind == StepKind.BLOOM) "Bloom" else "Pour ${pour.number}"
            if (!pour.detected) {
                findings += Finding(FindingLevel.INFO, "$label not detected", "No clear pour around ${pour.step.time.mmss()}.")
                continue
            }
            val startDelta = pour.startDelta
            if (startDelta != null && abs(startDelta) > 5 && pour.step.time > 0) {
                findings += Finding(FindingLevel.INFO,
                    "$label started ${roundHalfAway(abs(startDelta)).toInt()} s ${if (startDelta > 0) "late" else "early"}",
                    "Planned at ${pour.step.time.mmss()}, started at ${(pour.actualStart ?: 0.0).mmss()}.")
            }
            val weightDelta = pour.weightDelta
            if (weightDelta != null) {
                val weightTolerance = max(3.0, pour.target * 0.04)
                val reached = roundHalfAway(pour.reached ?: 0.0).toInt()
                if (weightDelta > weightTolerance) {
                    findings += Finding(FindingLevel.WARNING, "$label overpoured by ${roundHalfAway(weightDelta).toInt()} g",
                        "Reached $reached g, target ${pour.target.toInt()} g. Try a bigger ping buffer in Settings.")
                } else if (weightDelta < -weightTolerance) {
                    findings += Finding(FindingLevel.INFO, "$label underpoured by ${roundHalfAway(abs(weightDelta)).toInt()} g",
                        "Reached $reached g, target ${pour.target.toInt()} g.")
                }
            }
        }

        if (averageFlow != null) {
            val range = "${recipe.flowMin.toInt()}–${recipe.flowMax.toInt()} g/s"
            findings += when {
                flowFast -> Finding(FindingLevel.WARNING, "Fast pours (${fmt1(averageFlow)} g/s)",
                    "The recipe suggests $range. Fast, high pours add agitation and can dig channels.")
                flowSlow -> Finding(FindingLevel.INFO, "Slow pours (${fmt1(averageFlow)} g/s)",
                    "The recipe suggests $range. Very gentle pours add little agitation and the slurry cools down.")
                else -> Finding(FindingLevel.GOOD, "Pour rate on point (${fmt1(averageFlow)} g/s)", "Within the recipe's $range.")
            }
        }

        if (input.usedScale) {
            val delta = input.finalWeight - recipe.water
            findings += if (abs(delta) > max(4.0, recipe.water * 0.02)) {
                Finding(FindingLevel.WARNING, "Total water ${if (delta > 0) "over" else "under"} by ${roundHalfAway(abs(delta)).toInt()} g",
                    "Brewed at 1:${fmt1(ratio)} instead of ${recipe.ratioText}. More water = weaker but more extracted. Less water = stronger.")
            } else {
                Finding(FindingLevel.GOOD, "Ratio 1:${fmt1(ratio)}", "Right on the recipe's ${recipe.ratioText}.")
            }
        }

        if (input.waterTemp > 0) {
            val temp = input.waterTemp.toInt()
            when {
                roastIndex != null && roastIndex <= 1 && input.waterTemp < 92 -> findings += Finding(FindingLevel.WARNING,
                    "Cool water for a light roast", "Light roasts are dense and extract best at 93–100 °C. You used $temp °C.")
                roastIndex != null && roastIndex >= 3 && input.waterTemp > 93 -> findings += Finding(FindingLevel.WARNING,
                    "Hot water for a dark roast", "Dark roasts extract easily. 83–90 °C keeps bitterness down. You used $temp °C.")
                abs(input.waterTemp - recipe.temperature) > 2.5 -> findings += Finding(FindingLevel.INFO,
                    "Water $temp °C (recipe ${recipe.temperature.toInt()} °C)", "Hotter water extracts more. Cooler water extracts less.")
            }
        }

        val days = input.daysOffRoast
        if (days != null) {
            if (tooFresh) {
                findings += Finding(FindingLevel.INFO, "Very fresh beans ($days days)",
                    "Trapped CO₂ pushes water away and causes uneven extraction. Light roasts often peak 7–21 days after roasting.")
            } else if (stale) {
                findings += Finding(FindingLevel.INFO, "Beans are $days days off roast",
                    "Aromatics fade over time, so cups get flatter and more papery.")
            }
        }

        val ideal = input.filterIdealRoast
        if (ideal != null && roastIndex != null) {
            if (ideal == RoastLevel.DARK && roastIndex <= 1) {
                findings += Finding(FindingLevel.INFO, "Dark-roast paper with a light roast",
                    "${input.filterName} is tuned for dark roasts at about 83 °C. With light roasts, a T-92 or T-90 usually extracts better.")
            } else if (ideal == RoastLevel.LIGHT && roastIndex >= 3) {
                findings += Finding(FindingLevel.INFO, "Light-roast paper with a dark roast",
                    "${input.filterName} is tuned for light roasts. A T-83 or T-90 brings more body and less harshness to darker roasts.")
            }
        }

        if (input.grinder == null) {
            findings += Finding(FindingLevel.INFO, "No grinder selected",
                "Add your grinder in Gear and log the setting so suggestions can say exactly how many clicks to change.")
        } else if (input.grinder.currentValue == null) {
            findings += Finding(FindingLevel.INFO, "Grind setting not logged",
                "Log the grind setting so suggestions can give you an exact number.")
        }
        return findings
    }

    /**
     * If an earlier brew at a setting in the requested direction went too far the other way,
     * split the difference instead of jumping a full step.
     */
    fun bracketed(coarser: Boolean, current: Double, grinder: GrinderContext, history: List<PastBrew>): Double? {
        val spec = grinder.spec
        fun isCoarser(a: Double, than: Double) = if (spec.finerIsLower) a > than else a < than
        val candidates = history.mapNotNull { past ->
            val value = past.grindValue
            when {
                value == null || value == current -> null
                coarser -> if (isCoarser(value, current) &&
                    (TasteFeedback.SOUR in past.feedback || TasteFeedback.WEAK in past.feedback)) value else null
                else -> if (!isCoarser(value, current) &&
                    (TasteFeedback.BITTER in past.feedback || TasteFeedback.ASTRINGENT in past.feedback)) value else null
            }
        }
        val nearest = candidates.minByOrNull { abs(it - current) } ?: return null
        val mid = roundHalfAway((current + nearest) / 2 / spec.step) * spec.step
        return if (mid == current || mid == nearest) null else mid
    }
}
