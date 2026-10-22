package com.brewlog.app.brewing

import com.brewlog.app.domain.AppSettings
import com.brewlog.app.domain.InputLimits
import com.brewlog.app.domain.MachineSample
import com.brewlog.app.machine.GaggiMateStatus
import com.brewlog.app.machine.MachineManager
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

enum class BrewPhase {
    /** Weighing the beans on the tared scale (optional, before the brewer goes on). */
    DOSING,
    PREPARING, ARMED, BREWING, FINISHED,
}

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
    /** The bean dose read from the scale, null when the beans weren't weighed. */
    val weighedDose: Double? = null,
    val doseStatus: BeanDosing.Status = BeanDosing.Status.EMPTY,
    /** Espresso: pressure/temperature/flow recorded during the shot. */
    val machineSamples: List<MachineSample> = emptyList(),
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
    private val machine: MachineManager? = null,
    /** Live pressure from the BOOKOO Espresso Monitor is available (readings arrive via [monitorReading]). */
    private val monitorReady: () -> Boolean = { false },
    private val prepareMonitor: (Recipe) -> Unit = {},
) {
    val isEspresso: Boolean get() = recipe.isEspresso

    /** Espresso with a connected machine: the shot timer starts and stops with the machine's pump. */
    val followsMachine: Boolean get() = isEspresso && machine?.isConnected == true

    /** Espresso with live pressure, from the BOOKOO Espresso Monitor or the machine. */
    val hasPressure: Boolean get() = isEspresso && (monitorReady() || (machine?.isConnected == true && machine.status.hasPressure != false))

    /** The weight comes from the scale connected to the espresso machine instead of BrewLog's own connection. */
    private var weighsViaMachine = false
    private val machineSamples = ArrayList<MachineSample>()
    private var lastMachineSampleT = -1.0

    var usesScale: Boolean = scale.isReady || (recipe.isEspresso && machine?.isConnected == true && machine.status.hasWeight)
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
    private var weighedDose: Double? = null
    private var dosePinged = false
    private var prepared = false
    private val pourIndices: List<Int> =
        recipe.steps.indices.filter { recipe.steps[it].kind.isPour && recipe.steps[it].target != null }

    private val _state = MutableStateFlow(BrewSnapshot(usesScale = usesScale))
    val state: StateFlow<BrewSnapshot> = _state.asStateFlow()

    /** Water poured: the max weight seen, so lifting the dripper at the end doesn't distort it. */
    val finalWeight: Double get() = if (usesScale) maxWeight else recipe.water

    fun recordedSamples(): List<WeightSample> = samples.toList()

    fun recordedMachineSamples(): List<MachineSample> = machineSamples.toList()

    // MARK: Weighing the beans

    /** The planned bean dose (the recipe is already scaled to it). */
    val plannedDose: Double get() = recipe.dose

    /** The dose to save with the brew. */
    val dose: Double get() = weighedDose ?: plannedDose

    /** Weighing the beans needs a scale. */
    val canWeighBeans: Boolean get() = scale.isReady && (phase == BrewPhase.PREPARING || phase == BrewPhase.DOSING)

    /** Called once when the live screen opens: starts by weighing the beans if that's switched on. */
    fun prepare() {
        // Only once per brew, so recreating the screen (e.g. rotating) doesn't ask again.
        if (prepared) return
        prepared = true
        if (settings().weighBeansFirst) weighBeans()
    }

    /** Tare the scale and weigh the beans against the planned dose. */
    fun weighBeans() {
        if (!scale.isReady || phase != BrewPhase.PREPARING) return
        phase = BrewPhase.DOSING
        dosePinged = false
        scale.prepareForDosing(plannedDose)
        publish()
    }

    /** Keep what is on the scale as the dose for this brew. */
    fun acceptDose() {
        if (phase != BrewPhase.DOSING) return
        weighedDose = BeanDosing.acceptedDose(weight, plannedDose)
        scale.dosingFinished()
        phase = BrewPhase.PREPARING
        publish()
    }

    fun skipDosing() {
        if (phase != BrewPhase.DOSING) return
        scale.dosingFinished()
        phase = BrewPhase.PREPARING
        publish()
    }

    // MARK: Lifecycle

    /** Listens to the machine (espresso only). Returns the cleanup. */
    fun attach(): () -> Unit {
        val m = machine
        if (!isEspresso || m == null) return {}
        val offShot = m.onShot { started, at -> machineShot(started, at) }
        val offReading = m.onReading { status, at -> machineReading(status, at) }
        return { offShot(); offReading() }
    }

    /** "Ready": tare the scale and wait for the first pour. */
    fun ready() {
        weighsViaMachine = !scale.isReady && isEspresso && machine?.isConnected == true && machine.status.hasWeight
        usesScale = scale.isReady || weighsViaMachine
        phase = BrewPhase.ARMED
        armMs = clock()
        zeroConfirmed = false
        retareSent = false
        recent.clear()
        if (weighsViaMachine) machine?.tareScale() else if (usesScale) scale.prepareForBrew(recipe)
        if (followsMachine) machine?.prepareForShot(recipe)
        if (isEspresso) prepareMonitor(recipe)
        publish()
    }

    /** Espresso: starts the shot on the machine if it is connected, otherwise just the timer. */
    fun startShot() {
        if (followsMachine) machine?.startShot() else startManually()
    }

    private fun machineShot(started: Boolean, atMs: Long) {
        if (started) {
            when (phase) {
                BrewPhase.DOSING, BrewPhase.PREPARING -> { skipDosing(); ready(); begin(atMs) }
                BrewPhase.ARMED -> begin(atMs)
                else -> Unit
            }
        } else if (phase == BrewPhase.BREWING) {
            // The pump stopped. Give the last drops a few seconds, then finish.
            stopRequestedAt = clock()
        }
    }

    private fun machineReading(status: GaggiMateStatus, atMs: Long) {
        val grams = status.weight
        if (weighsViaMachine && grams != null) ingest(grams, atMs)
        // With the pressure sensor connected, its (faster, group-head) readings make the curve.
        if (monitorReady()) return
        recordPressure(status.pressure ?: 0.0, status.temperature, status.flow, atMs)
    }

    /** A reading from the BOOKOO Espresso Monitor. */
    fun monitorReading(bar: Double, atMs: Long) {
        if (!isEspresso) return
        // Without a machine connection, rising pressure means the pump started: start the shot timer.
        if (phase == BrewPhase.ARMED && !followsMachine && bar >= 1) begin(atMs)
        val status = if (machine?.isConnected == true) machine.status else null
        recordPressure(bar, status?.temperature, status?.flow, atMs)
    }

    private fun recordPressure(bar: Double, temperature: Double?, flow: Double?, atMs: Long) {
        if (phase != BrewPhase.BREWING || machineSamples.size >= MAX_SAMPLES) return
        val start = startMs ?: return
        val t = (atMs - start) / 1000.0
        if (t - lastMachineSampleT < 0.2) return
        lastMachineSampleT = t
        machineSamples.add(MachineSample(
            t = roundHalfAway(t * 100) / 100, p = roundHalfAway(bar * 100) / 100,
            c = temperature?.let { roundHalfAway(it * 10) / 10 }, f = flow?.let { roundHalfAway(it * 100) / 100 },
        ))
    }

    /** Set when the machine stopped the pump; the brew finishes 3 s later (see [tick]). */
    private var stopRequestedAt: Long? = null

    fun startManually() = begin(clock())

    fun finish() {
        if (phase != BrewPhase.BREWING) return
        val start = startMs ?: return
        elapsed = (clock() - start) / 1000.0
        phase = BrewPhase.FINISHED
        if (usesScale) {
            appendSample(elapsed, weight, force = true)
            if (!weighsViaMachine) scale.brewFinished()
        }
        // Ending the brew by hand also stops the pump if the machine is still pulling the shot.
        if (followsMachine && machine?.status?.isBrewing == true) machine.stopShot()
        publish()
    }

    /** Brew discarded mid-way: stop the scale timer / demo simulation too. */
    fun discard() {
        if (phase == BrewPhase.DOSING) scale.dosingFinished()
        if (usesScale && !weighsViaMachine && (phase == BrewPhase.ARMED || phase == BrewPhase.BREWING)) scale.brewFinished()
        if (isEspresso) machine?.cancelShot()
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
            BrewPhase.DOSING -> {
                // One ping when the dose is reached, so you can stop adding beans without staring at the number.
                if (!dosePinged && BeanDosing.status(grams, plannedDose) == BeanDosing.Status.ON_TARGET) {
                    dosePinged = true
                    onCue(BrewCue.TARGET)
                }
            }
            BrewPhase.ARMED -> {
                if (!usesScale) return
                val arm = armMs ?: return
                if (!zeroConfirmed) {
                    if (abs(grams) < 1.0 && atMs - arm > 250) {
                        zeroConfirmed = true
                    } else if (atMs - arm > 3_000 && !retareSent) {
                        if (weighsViaMachine) machine?.tareScale() else scale.tare()
                        retareSent = true
                    }
                } else if (grams >= settings().autoStartThreshold && !followsMachine) {
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
            val stop = stopRequestedAt
            if (elapsed >= InputLimits.MAX_BREW_SECONDS || (stop != null && now - stop >= 3_000)) {
                stopRequestedAt = null
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
        machineSamples.clear()
        lastMachineSampleT = -1.0
        stopRequestedAt = null
        if (usesScale && !weighsViaMachine) scale.brewStarted()
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
            weighedDose = weighedDose,
            doseStatus = BeanDosing.status(weight, plannedDose),
            machineSamples = machineSamples.toList(),
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
