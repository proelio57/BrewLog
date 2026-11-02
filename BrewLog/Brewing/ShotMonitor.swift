import Foundation

/// Decides during an espresso shot when to stop (just before the target yield, so the last drips land on it) and
/// when the shot is over (the weight has settled near the yield), and keeps the live numbers. Pure, so it is tested
/// without a scale or a machine; `BrewSession` feeds it the readings.
struct ShotMonitor {
    enum Action: Equatable {
        case none, stop, finish
    }

    let yield: Double
    let dose: Double
    let stopLag: Double
    let autoStop: Bool

    /// Seconds into the shot of the first gram in the cup.
    private(set) var firstDropsTime: TimeInterval?
    private(set) var stopped = false
    private var finished = false
    private var lastGrams: Double = 0
    private var recent: [(t: TimeInterval, grams: Double)] = []

    /// Readings older than this don't count for "settled".
    static let settleWindow: TimeInterval = 1.5
    static let settleTolerance = 0.3
    static let settleMinimumReadings = 4
    /// The shot only finishes by itself once this share of the yield is in the cup.
    static let finishShare = 0.9

    init(yield: Double, dose: Double, stopLag: Double, autoStop: Bool) {
        self.yield = yield
        self.dose = dose
        self.stopLag = stopLag
        self.autoStop = autoStop
    }

    /// The ratio so far (grams in the cup per gram of coffee), nil before the first gram or without a dose.
    var liveRatio: Double? {
        guard dose > 0, lastGrams >= 1 else { return nil }
        return lastGrams / dose
    }

    mutating func ingest(grams: Double, flow: Double, at t: TimeInterval) -> Action {
        guard grams.isFinite, t.isFinite else { return .none }
        lastGrams = grams
        if firstDropsTime == nil && grams >= 1 { firstDropsTime = t }
        recent.append((t, grams))
        recent.removeAll { t - $0.t > Self.settleWindow }

        if autoStop, yield > 0, !stopped, Self.shouldStop(weight: grams, flow: flow, yield: yield, lag: stopLag) {
            stopped = true
            return .stop
        }
        if yield > 0, !finished, grams >= yield * Self.finishShare, Self.isSettled(recent, now: t) {
            finished = true
            return .finish
        }
        return .none
    }

    /// Stop when the weight plus what is still on its way (flow × lag) reaches the yield. A negative flow (cup
    /// bumped, scale noise) counts as none.
    static func shouldStop(weight: Double, flow: Double, yield: Double, lag: Double) -> Bool {
        weight + max(flow, 0) * max(lag, 0) >= yield
    }

    /// Enough recent readings, all close together: nothing is dripping any more.
    static func isSettled(_ readings: [(t: TimeInterval, grams: Double)], now: TimeInterval) -> Bool {
        let window = readings.filter { now - $0.t <= settleWindow }.map(\.grams)
        guard window.count >= settleMinimumReadings, let low = window.min(), let high = window.max() else { return false }
        return high - low <= 2 * settleTolerance
    }

    /// The brew temperature to save: GaggiMate's target wins (the machine's settings are always right), then the
    /// measured average, then the recipe. Implausible values (outside 70–105 °C) are skipped.
    static func shotTemperature(recipe: Double, machineTarget: Double?, measuredAverage: Double?) -> Double {
        for value in [machineTarget, measuredAverage] {
            if let value, value.isFinite, (70...105).contains(value) { return value }
        }
        return recipe
    }

    /// The pressure the shot is judged against: GaggiMate's target (1–15 bar) wins over the recipe's.
    static func targetPressure(recipe: Double?, machineTarget: Double?) -> Double? {
        if let machineTarget, machineTarget.isFinite, (1...15).contains(machineTarget) { return machineTarget }
        return recipe
    }
}
