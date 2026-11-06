import Foundation
import Shared

/// Cleans up the scale's weight curve: single-reading spikes (a bump, a drop of water on the edge), the final
/// weight of a brew and the flow shown in the chart. The logic lives in Kotlin (android/shared,
/// `com.brewlog.app.analysis.WeightCleanup`), shared with Android and the web; this converts at the boundary.
enum WeightCleanup {
    private static var kotlin: Shared.WeightCleanup { Shared.WeightCleanup.shared }

    private static func toKotlin(_ samples: [WeightSample]) -> [Shared.WeightSample] {
        samples.map { Shared.WeightSample(t: $0.t, w: $0.w) }
    }

    /// Each reading replaced by the median of itself and its two neighbours on either side: a lone spike
    /// disappears, a real step (a pour) stays.
    static func despiked(_ samples: [WeightSample]) -> [WeightSample] {
        kotlin.despiked(samples: toKotlin(samples)).map { WeightSample(t: $0.t, w: $0.w) }
    }

    /// The weight a brew ended with: the value the scale stayed on longest near the end, not the maximum or the
    /// last reading. Nil without a usable curve.
    static func settledFinalWeight(_ samples: [WeightSample]) -> Double? {
        kotlin.settledFinalWeight(samples: toKotlin(samples))?.doubleValue
    }

    /// Flow for the chart: from the despiked curve over a 2 s window, then averaged over five readings.
    static func smoothedFlows(_ samples: [WeightSample]) -> [Double] {
        kotlin.smoothedFlows(samples: toKotlin(samples)).map(\.doubleValue)
    }
}
