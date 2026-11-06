import Foundation

/// Cleans up the scale's weight curve: single-reading spikes (a bump, a drop of water on the edge), the final
/// weight of a brew and the flow shown in the chart.
enum WeightCleanup {
    /// Each reading replaced by the median of itself and its two neighbours on either side: a lone spike
    /// disappears, a real step (a pour) stays.
    static func despiked(_ samples: [WeightSample]) -> [WeightSample] {
        guard samples.count >= 5 else { return samples }
        return samples.indices.map { i in
            let window = samples[max(i - 2, 0)...min(i + 2, samples.count - 1)].map(\.w).sorted()
            return WeightSample(t: samples[i].t, w: window[window.count / 2])
        }
    }

    /// The weight a brew ended with: the value the scale stayed on longest near the end, not the maximum or the
    /// last reading. Only readings within 95 % of the (despiked) peak count, so lifting the dripper afterwards
    /// doesn't either. Readings are grouped to 0.5 g; the result keeps 0.1 g. Nil without a usable curve.
    static func settledFinalWeight(_ samples: [WeightSample]) -> Double? {
        let cleaned = despiked(samples)
        guard let peak = cleaned.map(\.w).max(), peak > 0 else { return nil }
        let threshold = peak * 0.95
        var dwell: [Double: (time: Double, weighted: Double)] = [:]
        for i in cleaned.indices where cleaned[i].w >= threshold {
            // How long the scale showed this reading: until the next one (capped, in case of a pause in the data).
            let duration = i + 1 < cleaned.count ? min(max(cleaned[i + 1].t - cleaned[i].t, 0), 5) : 0
            let bucket = (cleaned[i].w * 2).rounded() / 2
            let current = dwell[bucket] ?? (0, 0)
            dwell[bucket] = (current.time + duration, current.weighted + cleaned[i].w * duration)
        }
        guard let best = dwell.max(by: { ($0.value.time, $0.key) < ($1.value.time, $1.key) }), best.value.time > 0 else {
            return (peak * 10).rounded() / 10
        }
        return (best.value.weighted / best.value.time * 10).rounded() / 10
    }

    /// Flow for the chart: from the despiked curve over a 2 s window, then averaged over five readings.
    static func smoothedFlows(_ samples: [WeightSample]) -> [Double] {
        let flows = BrewAnalyzer.centeredFlows(despiked(samples), window: 2.0)
        guard flows.count >= 5 else { return flows }
        return flows.indices.map { i in
            let window = flows[max(i - 2, 0)...min(i + 2, flows.count - 1)]
            return window.reduce(0, +) / Double(window.count)
        }
    }
}
