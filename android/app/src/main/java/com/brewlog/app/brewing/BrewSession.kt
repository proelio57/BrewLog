package com.brewlog.app.brewing

import com.brewlog.app.domain.AppSettings
import com.brewlog.app.domain.InputLimits
import com.brewlog.app.domain.PingLeadMode
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.WeightSample
import com.brewlog.app.domain.roundHalfAway
import com.brewlog.app.scale.ScaleCommands
import com.brewlog.app.scale.monotonicMillis
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max

enum class BrewCue {
    /** Short, high, soft "ding" just before the pour target is reached. */
    TARGET,
    /** Gentle two-note chime: time for the next step. */
    NEXT_STEP,
    /** Calm three-note phrase: target brew time reached. */
    FINISH,
    /** Very soft tick for the 3-2-1 countdown. */
    TICK,
}

enum class BrewPhase { PREPARING, ARMED, BREWING, FINISHED }

/** Immutable snapshot of the live brew for the UI. */
data class BrewSnapshot(
    val phase: BrewPhase = BrewPhase.PREPARING,
    val usesScale: Boolean = false,
    val elapsed: Double = 0.0,
    val weight: Double = 0.0,
    val flowRate: Double = 0.0,
    val samples: List<WeightSample> = emptyList(),
    val zeroConfirmed: Boolean = false,
    val currentStepIndex: Int? = null,
    val nextStepIndex: Int? = null,
    val timeToNextStep: Double? = null,
    val countdownProgress: Double = 0.0,
    val activeTarget: Double? = null,
    val activePourBase: Double = 0.0,
    val overpour: Double? = null,
    val pingLead: Double = 1.5,
    val flash: BrewCue? = null,
)

/**
 * Drives a live brew: auto-start on first pour, step timing, buffered target pings, countdowns and recording.
 * 1:1 port of BrewSession.swift. Feed it [ingest] (scale readings) and [tick] (every 50 ms).
 */
class BrewSession(
    val recipe: Recipe,
    private val scale: ScaleCommands,
    private val settings: () -> AppSettings,
    private val onCue: (BrewCue) -> Unit,
    private val clock: () -> Long = ::monotonicMillis,
) {
    var usesScale: Boolean = scale.isReady
        private set
    var phase: BrewPhase = BrewPhase.PREPARING
        private set
    var elapsed: Double = 0.0
        private set

    /** Called when a brew runs past the maximum duration (e.g. the user walked away). */
    var onAutoFinish: (() -> Unit)? = null

    private var weight = 0.0
    private var flowRate = 0.0
    private val samples = ArrayList<WeightSample>()
    private var maxWeight = 0.0
    private val targetPinged = HashSet<Int>()
    private val startPinged = HashSet<Int>()
    private var zeroConfirmed = false
    private var startMs: Long? = null
    private var armMs: Long? = null
    private val recent = ArrayDeque<Pair<Long, Double>>()
    private var lastSampleT = -1.0
    private var retareSent = false
    private var finishPinged = false
    private var lastTickSecond: Int? = null
    private var flash: BrewCue? = null
    private var flashUntil = 0L
    private val pourIndices: List<Int> =
        recipe.steps.indices.filter { recipe.steps[it].kind.isPour && recipe.steps[it].target != null }

    private val _state = MutableStateFlow(BrewSnapshot(usesScale = usesScale))
    val state: StateFlow<BrewSnapshot> = _state.asStateFlow()

    /** Water poured: the max weight seen, so lifting the dripper at the end doesn't distort it. */
    val finalWeight: Double get() = if (usesScale) maxWeight else recipe.water

    fun recordedSamples(): List<WeightSample> = samples.toList()

    // MARK: Lifecycle

    /** "Ready": tare the scale and wait for the first pour. */
    fun ready() {
        usesScale = scale.isReady
        phase = BrewPhase.ARMED
        armMs = clock()
        zeroConfirmed = false
        retareSent = false
        recent.clear()
        if (usesScale) scale.prepareForBrew(recipe)
        publish()
    }

    fun startManually() = begin(clock())

    fun finish() {
        if (phase != BrewPhase.BREWING) return
        val start = startMs ?: return
        elapsed = (clock() - start) / 1000.0
        phase = BrewPhase.FINISHED
        if (usesScale) {
            appendSample(elapsed, weight, force = true)
            scale.brewFinished()
        }
        publish()
    }

    /** Brew discarded mid-way: stop the scale timer / demo simulation too. */
    fun discard() {
        if (usesScale && (phase == BrewPhase.ARMED || phase == BrewPhase.BREWING)) scale.brewFinished()
    }

    // MARK: Engine

    fun ingest(grams: Double, atMs: Long) {
        if (!grams.isFinite()) return
        weight = grams
        recent.addLast(atMs to grams)
        while (recent.isNotEmpty() && atMs - recent.first().first > 3_000) recent.removeFirst()
        while (recent.size > MAX_RECENT_READINGS) recent.removeFirst()
        flowRate = slope(recent, 1.2, atMs)

        when (phase) {
            BrewPhase.ARMED -> {
                if (!usesScale) return
                val arm = armMs ?: return
                if (!zeroConfirmed) {
                    if (abs(grams) < 1.0 && atMs - arm > 250) {
                        zeroConfirmed = true
                    } else if (atMs - arm > 3_000 && !retareSent) {
                        scale.tare()
                        retareSent = true
                    }
                } else if (grams >= settings().autoStartThreshold) {
                    // Backdate the start to when the weight first left zero.
                    var onset = atMs
                    for ((time, value) in recent.reversed()) {
                        if (value > 0.3) onset = time else break
                    }
                    begin(onset)
                }
            }
            BrewPhase.BREWING -> {
                val start = startMs ?: return
                maxWeight = max(maxWeight, grams)
                appendSample((atMs - start) / 1000.0, grams, force = false)
                checkTargetPing()
            }
            else -> Unit
        }
    }

    fun tick() {
        val now = clock()
        if (flash != null && now >= flashUntil) flash = null
        if (phase == BrewPhase.BREWING) {
            val start = startMs ?: return
            elapsed = (now - start) / 1000.0
            if (elapsed >= InputLimits.MAX_BREW_SECONDS) {
                onAutoFinish?.invoke()
                return
            }
            checkStepStarts()
            checkCountdownTicks()
            checkFinishPing()
        }
        publish()
    }

    private fun begin(atMs: Long) {
        startMs = atMs
        elapsed = max((clock() - atMs) / 1000.0, 0.0)
        phase = BrewPhase.BREWING
        samples.clear()
        samples.add(WeightSample(0.0, 0.0))
        lastSampleT = 0.0
        if (usesScale) scale.brewStarted()
        // The first step at 0:00 is silent; just mark it as started.
        recipe.steps.forEachIndexed { index, step -> if (step.time <= 0) startPinged.add(index) }
        publish()
    }

    private fun checkStepStarts() {
        recipe.steps.forEachIndexed { index, step ->
            if (step.time > 0 && step.time <= elapsed && index !in startPinged) {
                startPinged.add(index)
                // Don't replay cues that were missed (e.g. app was in the background)
                if (elapsed - step.time < 2) fire(BrewCue.NEXT_STEP)
            }
        }
    }

    private fun checkCountdownTicks() {
        if (!settings().countdownTicks) return
        val remaining = timeToNextStep() ?: return
        val second = ceil(remaining).toInt()
        if (second in 1..3 && second != lastTickSecond && remaining < second) {
            lastTickSecond = second
            if (second - remaining < 0.2) onCue(BrewCue.TICK)
        }
    }

    private fun checkFinishPing() {
        if (finishPinged || !settings().finishPing || elapsed < recipe.targetTime) return
        finishPinged = true
        // Skip if a recipe step already chimes at this moment (e.g. "remove dripper")
        if (recipe.steps.any { abs(it.time - recipe.targetTime) < 1.5 }) return
        if (elapsed - recipe.targetTime < 2) fire(BrewCue.FINISH)
    }

    private fun checkTargetPing() {
        val index = activePourIndex() ?: return
        val target = recipe.steps[index].target ?: return
        if (index in targetPinged) return
        if (weight >= target - pingLead()) {
            targetPinged.add(index)
            fire(BrewCue.TARGET)
        }
    }

    private fun fire(cue: BrewCue) {
        onCue(cue)
        flash = cue
        flashUntil = clock() + 800
    }

    private fun appendSample(t: Double, grams: Double, force: Boolean) {
        if (!force && t - lastSampleT < 0.1) return
        if (samples.size >= MAX_SAMPLES) return
        lastSampleT = t
        samples.add(WeightSample(roundHalfAway(t * 100) / 100, roundHalfAway(grams * 10) / 10))
    }

    // MARK: Derived state

    private fun currentStepIndex(): Int? = recipe.steps.indexOfLast { it.time <= elapsed }.takeIf { it >= 0 }

    private fun nextStepIndex(): Int? = recipe.steps.indexOfFirst { it.time > elapsed }.takeIf { it >= 0 }

    private fun timeToNextStep(): Double? {
        if (phase != BrewPhase.BREWING) return null
        val next = nextStepIndex() ?: return null
        return recipe.steps[next].time - elapsed
    }

    private fun countdownProgress(): Double {
        if (phase != BrewPhase.BREWING) return 0.0
        val previous = currentStepIndex()?.let { recipe.steps[it].time } ?: 0.0
        val next = nextStepIndex()?.let { recipe.steps[it].time } ?: recipe.targetTime
        val span = max(next - previous, 1.0)
        return ((elapsed - previous) / span).coerceIn(0.0, 1.0)
    }

    /** The pour the user should be doing right now (allows starting up to 3 s early). */
    private fun activePourIndex(): Int? {
        if (pourIndices.isEmpty()) return null
        val t = if (phase == BrewPhase.BREWING) elapsed else 0.0
        var active = pourIndices.lastOrNull { recipe.steps[it].time <= t }
        val next = pourIndices.firstOrNull { recipe.steps[it].time > t }
        if (next != null && recipe.steps[next].time - t <= 3 && (active?.let { it in targetPinged } ?: true)) {
            active = next
        }
        return active ?: pourIndices.first()
    }

    private fun activePourBase(): Double {
        val active = activePourIndex() ?: return 0.0
        val position = pourIndices.indexOf(active)
        return if (position > 0) recipe.steps[pourIndices[position - 1]].target ?: 0.0 else 0.0
    }

    private fun overpour(): Double? {
        if (!usesScale) return null
        val target = activePourIndex()?.let { recipe.steps[it].target } ?: return null
        val over = weight - target
        return if (over > max(2.0, target * 0.02)) over else null
    }

    /** The current ping buffer in grams. */
    fun pingLead(): Double {
        val s = settings()
        return when (s.pingLeadMode) {
            PingLeadMode.FIXED -> max(s.pingLeadGrams, 0.0)
            // Water in the air + scale latency + human reaction time ≈ flow × reaction time.
            PingLeadMode.AUTO -> (max(flowRate, 0.0) * s.reactionTime + 1.0).coerceIn(1.5, 10.0)
        }
    }

    private fun publish() {
        _state.value = BrewSnapshot(
            phase = phase,
            usesScale = usesScale,
            elapsed = elapsed,
            weight = weight,
            flowRate = flowRate,
            samples = samples.toList(),
            zeroConfirmed = zeroConfirmed,
            currentStepIndex = currentStepIndex(),
            nextStepIndex = nextStepIndex(),
            timeToNextStep = timeToNextStep(),
            countdownProgress = countdownProgress(),
            activeTarget = activePourIndex()?.let { recipe.steps[it].target },
            activePourBase = activePourBase(),
            overpour = overpour(),
            pingLead = pingLead(),
            flash = flash,
        )
    }

    companion object {
        /** Hard limits so a forgotten brew or a misbehaving device can't grow memory without bound. */
        const val MAX_RECENT_READINGS = 120
        val MAX_SAMPLES = (InputLimits.MAX_BREW_SECONDS * 10).toInt() + 10

        /** Least-squares slope (g/s) over the last [window] seconds. */
        fun slope(readings: Collection<Pair<Long, Double>>, window: Double, nowMs: Long): Double {
            val points = readings.filter { (nowMs - it.first) / 1000.0 <= window }
            if (points.size < 3) return 0.0
            val t0 = points.first().first
            val xs = points.map { (it.first - t0) / 1000.0 }
            val ys = points.map { it.second }
            val meanX = xs.average()
            val meanY = ys.average()
            var numerator = 0.0
            var denominator = 0.0
            for (i in xs.indices) {
                numerator += (xs[i] - meanX) * (ys[i] - meanY)
                denominator += (xs[i] - meanX) * (xs[i] - meanX)
            }
            return if (denominator > 0.0001) numerator / denominator else 0.0
        }
    }
}
