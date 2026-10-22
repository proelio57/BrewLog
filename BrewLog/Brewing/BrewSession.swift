import Foundation
import Observation
import UIKit

/// Drives a live brew: auto-start on first pour, step timing, buffered target pings, countdowns and recording.
@Observable
final class BrewSession {
    enum Phase: Equatable {
        /// Weighing the beans on the tared scale (optional, before the brewer goes on).
        case dosing
        /// Waiting for the user to put the brewer on the scale and press Ready.
        case preparing
        /// Tared. Waiting for the first pour (scale) or a manual start.
        case armed
        case brewing
        case finished
    }

    let recipe: Recipe
    /// Whether live weight from a scale is used. Decided when Ready is pressed.
    private(set) var usesScale: Bool
    private(set) var phase: Phase = .preparing
    private(set) var elapsed: TimeInterval = 0
    private(set) var weight: Double = 0
    private(set) var flowRate: Double = 0
    private(set) var samples: [WeightSample] = []
    private(set) var maxWeight: Double = 0
    private(set) var targetPinged: Set<Int> = []
    private(set) var startPinged: Set<Int> = []
    private(set) var zeroConfirmed = false
    /// Briefly set after a cue so the UI can flash.
    private(set) var flash: BrewCue?
    /// Espresso: pressure, temperature and flow recorded from the machine during the shot.
    private(set) var machineSamples: [MachineSample] = []
    /// The bean dose read from the scale when the beans were weighed, nil when they weren't.
    private(set) var weighedDose: Double?

    @ObservationIgnored private let scale: ScaleManager
    @ObservationIgnored private let sound: SoundPlayer
    @ObservationIgnored private let voice = VoicePrompter.shared
    @ObservationIgnored private var previewed: Set<Int> = []
    @ObservationIgnored private let machine: MachineManager
    @ObservationIgnored private let monitor: PressureMonitor
    /// The weight comes from the scale connected to the espresso machine instead of BrewLog's own scale connection.
    @ObservationIgnored private var weighsViaMachine = false
    @ObservationIgnored private var lastMachineSampleT: Double = -1
    @ObservationIgnored private var startDate: Date?
    @ObservationIgnored private var armDate: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var recent: [(date: Date, grams: Double)] = []
    @ObservationIgnored private var lastSampleT: Double = -1
    @ObservationIgnored private var retareSent = false
    @ObservationIgnored private var finishPinged = false
    @ObservationIgnored private var dosePinged = false
    @ObservationIgnored private var prepared = false
    @ObservationIgnored private var lastTickSecond: Int?
    @ObservationIgnored private let pourIndices: [Int]
    @ObservationIgnored private let liveActivity = BrewLiveActivity()

    init(recipe: Recipe, scale: ScaleManager = .shared, sound: SoundPlayer = .shared, machine: MachineManager = .shared,
         monitor: PressureMonitor = .shared) {
        self.recipe = recipe
        self.scale = scale
        self.sound = sound
        self.machine = machine
        self.monitor = monitor
        self.usesScale = scale.isReady || (recipe.method.isEspresso && machine.isConnected && machine.status.hasWeight)
        self.pourIndices = recipe.steps.indices.filter { recipe.steps[$0].kind.isPour && recipe.steps[$0].target != nil }
    }

    // MARK: Lifecycle

    func activate() {
        sound.prepare()
        scale.onWeight = { [weak self] grams, date in
            guard self?.weighsViaMachine == false else { return }
            self?.ingest(grams, at: date)
        }
        if isEspresso {
            machine.onShot = { [weak self] started, date in self?.machineShot(started: started, at: date) }
            machine.onReading = { [weak self] status, date in self?.machineReading(status, at: date) }
            monitor.onPressure = { [weak self] bar, date in self?.monitorReading(bar, at: date) }
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if AppSettings.keepAwake { UIApplication.shared.isIdleTimerDisabled = true }
        // Only once per brew, so the view appearing again doesn't ask again.
        if !prepared {
            prepared = true
            if AppSettings.weighBeansFirst { weighBeans() }
        }
    }

    func deactivate() {
        timer?.invalidate()
        timer = nil
        scale.onWeight = nil
        if isEspresso {
            machine.onShot = nil
            machine.onReading = nil
            machine.cancelShot()
            monitor.onPressure = nil
            monitor.shotFinished()
        }
        if phase == .dosing { scale.dosingFinished() }
        // Brew discarded mid-way: stop the scale timer / demo simulation too.
        if usesScale && !weighsViaMachine && (phase == .armed || phase == .brewing) { scale.brewFinished() }
        liveActivity.end(nil)
        voice.stop()
        sound.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Weighing the beans

    /// The planned bean dose (the recipe is already scaled to it).
    var plannedDose: Double { recipe.dose }

    /// The dose to save with the brew.
    var dose: Double { weighedDose ?? plannedDose }

    /// Weighing the beans needs BrewLog's own scale.
    var canWeighBeans: Bool { scale.isReady && (phase == .preparing || phase == .dosing) }

    var doseStatus: BeanDosing.Status { BeanDosing.status(weight: weight, dose: plannedDose) }

    /// Tare the scale and weigh the beans against the planned dose.
    func weighBeans() {
        guard scale.isReady, phase == .preparing else { return }
        phase = .dosing
        dosePinged = false
        scale.prepareForDosing(dose: plannedDose)
        Haptics.tap()
    }

    /// Keep what is on the scale as the dose for this brew.
    func acceptDose() {
        guard phase == .dosing else { return }
        weighedDose = BeanDosing.acceptedDose(weight: weight, planned: plannedDose)
        scale.dosingFinished()
        phase = .preparing
        Haptics.tap()
    }

    func skipDosing() {
        guard phase == .dosing else { return }
        scale.dosingFinished()
        phase = .preparing
    }

    /// "Ready": tare the scale and wait for the first pour.
    func ready() {
        weighsViaMachine = !scale.isReady && isEspresso && machine.isConnected && machine.status.hasWeight
        usesScale = scale.isReady || weighsViaMachine
        phase = .armed
        armDate = Date()
        zeroConfirmed = false
        retareSent = false
        recent.removeAll()
        if weighsViaMachine {
            machine.tareScale()
        } else if usesScale {
            scale.prepareForBrew(recipe: recipe)
        }
        if followsMachine { machine.prepareForShot(recipe: recipe) }
        if isEspresso { monitor.prepareForShot(recipe: recipe) }
        Haptics.tap()
    }

    // MARK: Espresso machine

    var isEspresso: Bool { recipe.method.isEspresso }

    /// Espresso with a connected machine: the shot timer starts and stops with the machine's pump.
    var followsMachine: Bool { isEspresso && machine.isConnected }

    /// Espresso with live pressure, from the BOOKOO Espresso Monitor or the machine.
    var hasPressure: Bool { isEspresso && (monitor.isReady || (machine.isConnected && machine.status.hasPressure != false)) }

    private func machineShot(started: Bool, at date: Date) {
        if started {
            switch phase {
            case .dosing, .preparing:
                skipDosing()
                ready()
                begin(at: date)
            case .armed:
                begin(at: date)
            default:
                break
            }
        } else if phase == .brewing {
            // The pump stopped. Give the last drops a few seconds, then finish.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.phase == .brewing else { return }
                self.onAutoFinish?()
            }
        }
    }

    private func machineReading(_ status: GaggiMateStatus, at date: Date) {
        if weighsViaMachine, let grams = status.weight { ingest(grams, at: date) }
        // With the pressure sensor connected, its (faster, group-head) readings make the curve.
        guard !monitor.isReady else { return }
        recordPressure(status.pressure ?? 0, temperature: status.temperature, flow: status.flow, at: date)
    }

    private func monitorReading(_ bar: Double, at date: Date) {
        // Without a machine connection, rising pressure means the pump started: start the shot timer.
        if phase == .armed && !followsMachine && bar >= 1 { begin(at: date) }
        let status = machine.isConnected ? machine.status : nil
        recordPressure(bar, temperature: status?.temperature, flow: status?.flow, at: date)
    }

    private func recordPressure(_ bar: Double, temperature: Double?, flow: Double?, at date: Date) {
        guard phase == .brewing, let startDate, machineSamples.count < Self.maxSamples else { return }
        let t = date.timeIntervalSince(startDate)
        guard t - lastMachineSampleT >= 0.2 else { return }
        lastMachineSampleT = t
        machineSamples.append(MachineSample(t: (t * 100).rounded() / 100,
                                            p: (bar * 100).rounded() / 100,
                                            c: temperature.map { ($0 * 10).rounded() / 10 },
                                            f: flow.map { ($0 * 100).rounded() / 100 }))
    }

    func startManually() {
        begin(at: Date())
    }

    func finish() {
        guard phase == .brewing, let startDate else { return }
        elapsed = Date().timeIntervalSince(startDate)
        phase = .finished
        if usesScale {
            appendSample(t: elapsed, grams: weight, force: true)
            if !weighsViaMachine { scale.brewFinished() }
        }
        // Ending the session by hand also stops the pump if the machine is still pulling the shot.
        if followsMachine && machine.status.isBrewing { machine.stopShot() }
        timer?.invalidate()
        timer = nil
        liveActivity.end(liveActivityState(), keepFor: 120)
        // Let the app suspend in the background again (the audio engine keeps it awake while brewing).
        sound.stop()
        Haptics.tap()
    }

    /// Water poured: the max weight seen, so lifting the dripper at the end doesn't distort it.
    var finalWeight: Double { usesScale ? maxWeight : recipe.water }

    // MARK: Derived state for the UI

    var currentStepIndex: Int? {
        recipe.steps.lastIndex(where: { $0.time <= elapsed })
    }

    var nextStepIndex: Int? {
        recipe.steps.firstIndex(where: { $0.time > elapsed })
    }

    /// Seconds until the next step starts.
    var timeToNextStep: TimeInterval? {
        guard phase == .brewing, let next = nextStepIndex else { return nil }
        return recipe.steps[next].time - elapsed
    }

    /// Progress (0…1) of the countdown ring toward the next step or the target time.
    var countdownProgress: Double {
        guard phase == .brewing else { return 0 }
        let previousTime = currentStepIndex.map { recipe.steps[$0].time } ?? 0
        let nextTime = nextStepIndex.map { recipe.steps[$0].time } ?? recipe.targetTime
        let span = max(nextTime - previousTime, 1)
        return min(max((elapsed - previousTime) / span, 0), 1)
    }

    /// The pour the user should be doing right now (allows starting up to 3 s early).
    var activePourIndex: Int? {
        guard !pourIndices.isEmpty else { return nil }
        let t = phase == .brewing ? elapsed : 0
        var active = pourIndices.last(where: { recipe.steps[$0].time <= t })
        if let next = pourIndices.first(where: { recipe.steps[$0].time > t }),
           recipe.steps[next].time - t <= 3,
           active.map({ targetPinged.contains($0) }) ?? true {
            active = next
        }
        return active ?? pourIndices.first
    }

    var activeTarget: Double? {
        activePourIndex.flatMap { recipe.steps[$0].target }
    }

    /// The previous cumulative target, used to show progress within the current pour.
    var activePourBase: Double {
        guard let active = activePourIndex, let position = pourIndices.firstIndex(of: active), position > 0 else { return 0 }
        return recipe.steps[pourIndices[position - 1]].target ?? 0
    }

    /// Grams over the active target (positive = overpour) once beyond a small tolerance.
    var overpour: Double? {
        guard usesScale, let target = activeTarget else { return nil }
        let over = weight - target
        return over > max(2, target * 0.02) ? over : nil
    }

    /// The current ping buffer in grams.
    var pingLead: Double {
        switch AppSettings.pingLeadMode {
        case .fixed:
            return max(AppSettings.pingLeadGrams, 0)
        case .auto:
            // Water in the air + scale latency + human reaction time ≈ flow × reaction time.
            let lead = max(flowRate, 0) * AppSettings.reactionTime + 1.0
            return min(max(lead, 1.5), 10)
        }
    }

    var isPastTargetTime: Bool { elapsed >= recipe.targetTime }

    // MARK: Engine

    /// Hard limits so a forgotten brew or a misbehaving device can't grow memory without bound.
    static let maxRecentReadings = 120
    static let maxSamples = Int(InputLimits.maxBrewSeconds * 10) + 10

    private func ingest(_ grams: Double, at date: Date) {
        guard grams.isFinite else { return }
        weight = grams
        recent.append((date, grams))
        recent.removeAll { date.timeIntervalSince($0.date) > 3 }
        if recent.count > Self.maxRecentReadings { recent.removeFirst(recent.count - Self.maxRecentReadings) }
        flowRate = Self.slope(of: recent, window: 1.2, now: date)

        switch phase {
        case .armed:
            guard usesScale, let armDate else { return }
            if !zeroConfirmed {
                if abs(grams) < 1.0 && date.timeIntervalSince(armDate) > 0.25 {
                    zeroConfirmed = true
                } else if date.timeIntervalSince(armDate) > 3, !retareSent {
                    if weighsViaMachine { machine.tareScale() } else { scale.tare() }
                    retareSent = true
                }
            } else if grams >= AppSettings.autoStartThreshold && !followsMachine {
                // Backdate the start to when the weight first left zero.
                var onset = date
                for reading in recent.reversed() {
                    if reading.grams > 0.3 { onset = reading.date } else { break }
                }
                begin(at: onset)
            }
        case .dosing:
            // One ping when the dose is reached, so you can stop adding beans without staring at the number.
            if !dosePinged && doseStatus == .onTarget {
                dosePinged = true
                sound.cue(.target)
            }
        case .brewing:
            guard let startDate else { return }
            maxWeight = max(maxWeight, grams)
            appendSample(t: date.timeIntervalSince(startDate), grams: grams, force: false)
            checkTargetPing()
        default:
            break
        }
    }

    private func begin(at date: Date) {
        startDate = date
        elapsed = max(Date().timeIntervalSince(date), 0)
        phase = .brewing
        samples = [WeightSample(t: 0, w: 0)]
        lastSampleT = 0
        if usesScale && !weighsViaMachine { scale.brewStarted() }
        machineSamples = []
        lastMachineSampleT = -1
        // The first step at 0:00 is silent; just mark it as started.
        for (index, step) in recipe.steps.enumerated() where step.time <= 0 {
            startPinged.insert(index)
        }
        if let first = recipe.steps.first(where: { $0.time <= 0 }) { voice.say(StepAnnouncement.text(for: first), delay: 0) }
        liveActivity.start(recipe: recipe, state: liveActivityState())
    }

    /// Called when a brew runs past the maximum duration (e.g. the user walked away).
    @ObservationIgnored var onAutoFinish: (() -> Void)?

    private func tick() {
        guard phase == .brewing, let startDate else { return }
        elapsed = Date().timeIntervalSince(startDate)
        if elapsed >= InputLimits.maxBrewSeconds {
            onAutoFinish?()
            return
        }
        checkStepStarts()
        checkStepPreview()
        checkCountdownTicks()
        checkFinishPing()
        liveActivity.update(liveActivityState())
    }

    /// What the Lock Screen / Dynamic Island shows right now.
    private func liveActivityState() -> BrewLiveActivity.State {
        let start = startDate ?? Date()
        let finished = phase == .finished
        let current = currentStepIndex.map { recipe.steps[$0] }
        var nextLabel: String?
        var nextDate: Date?
        if let next = nextStepIndex.map({ recipe.steps[$0] }) {
            nextLabel = next.headline
            nextDate = start.addingTimeInterval(next.time)
        } else if elapsed < recipe.targetTime {
            nextLabel = "Target time"
            nextDate = start.addingTimeInterval(recipe.targetTime)
        }
        return BrewLiveActivity.State(
            startDate: start,
            finishedAt: finished ? start.addingTimeInterval(elapsed) : nil,
            stepTitle: finished ? "Brew finished" : (current?.headline ?? "Brewing"),
            stepSymbol: finished ? "checkmark.circle.fill" : (current?.kind.symbol ?? "drop.fill"),
            nextLabel: finished ? nil : nextLabel,
            nextDate: finished ? nil : nextDate,
            // Whole grams: the Lock Screen doesn't need decimals, and it avoids updates for scale noise.
            weight: usesScale ? (finished ? finalWeight : max(weight, 0)).rounded() : nil,
            pourTarget: usesScale && !finished ? activeTarget : nil,
            pourBase: activePourBase
        )
    }

    private func checkStepStarts() {
        for (index, step) in recipe.steps.enumerated() where step.time > 0 && step.time <= elapsed && !startPinged.contains(index) {
            startPinged.insert(index)
            // Don't replay cues that were missed (e.g. app was suspended)
            if elapsed - step.time < 2 {
                fire(.nextStep)
                voice.say(StepAnnouncement.text(for: step))
            }
        }
    }

    /// "Next, pour to 250 grams." a few seconds ahead, when the previous step leaves time for it.
    private func checkStepPreview() {
        guard AppSettings.voicePrompts, AppSettings.voicePreview, let next = nextStepIndex, !previewed.contains(next),
              let remaining = timeToNextStep, remaining <= StepAnnouncement.leadTime else { return }
        previewed.insert(next)
        let previousStart = currentStepIndex.map { recipe.steps[$0].time } ?? 0
        let gap = recipe.steps[next].time - previousStart
        if remaining > StepAnnouncement.leadTime - 1, gap >= StepAnnouncement.leadTime + 6 {
            voice.say(StepAnnouncement.preview(for: recipe.steps[next]), delay: 0)
        }
    }

    /// 3-2-1 ticks before each step, or (by default) only before the valve has to be opened or closed.
    private func checkCountdownTicks() {
        guard let next = nextStepIndex, let remaining = timeToNextStep else { return }
        let valve = AppSettings.valveCountdown && recipe.valveChange(at: next) != nil
        guard AppSettings.countdownTicks || valve else { return }
        let second = Int(remaining.rounded(.up))
        if (1...3).contains(second), second != lastTickSecond, remaining < Double(second) {
            lastTickSecond = second
            guard Double(second) - remaining < 0.2 else { return }
            // Valve ticks also buzz, so you notice them with the kettle in your hand.
            if valve { sound.cue(.tick) } else { sound.play(.tick) }
        }
    }

    private func checkFinishPing() {
        guard !finishPinged, AppSettings.finishPing, elapsed >= recipe.targetTime else { return }
        finishPinged = true
        // Skip if a recipe step already chimes at this exact moment (e.g. "remove dripper")
        if recipe.steps.contains(where: { abs($0.time - recipe.targetTime) < 1.5 }) { return }
        if elapsed - recipe.targetTime < 2 {
            fire(.finish)
            voice.say(StepAnnouncement.finished)
        }
    }

    private func checkTargetPing() {
        guard let index = activePourIndex, let target = recipe.steps[index].target, !targetPinged.contains(index) else { return }
        if weight >= target - pingLead {
            targetPinged.insert(index)
            fire(.target)
        }
    }

    private func fire(_ cue: BrewCue) {
        sound.cue(cue)
        flash = cue
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            if self?.flash == cue { self?.flash = nil }
        }
    }

    private func appendSample(t: Double, grams: Double, force: Bool) {
        guard force || t - lastSampleT >= 0.1, samples.count < Self.maxSamples else { return }
        lastSampleT = t
        samples.append(WeightSample(t: (t * 100).rounded() / 100, w: (grams * 10).rounded() / 10))
    }

    /// Least-squares slope (g/s) over the last `window` seconds.
    static func slope(of readings: [(date: Date, grams: Double)], window: Double, now: Date) -> Double {
        let points = readings.filter { now.timeIntervalSince($0.date) <= window }
        guard points.count >= 3, let first = points.first else { return 0 }
        let xs = points.map { $0.date.timeIntervalSince(first.date) }
        let ys = points.map(\.grams)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var numerator = 0.0, denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator > 0.0001 else { return 0 }
        return numerator / denominator
    }
}
