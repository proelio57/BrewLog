import ActivityKit
import Foundation

/// Data for the brew Live Activity (Lock Screen and Dynamic Island).
/// Compiled into both the app and the BrewLogWidgets extension.
struct BrewActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the brew timer started. The widget counts up from here by itself.
        var startDate: Date
        /// Set when the brew is finished; the timer then stops at this moment.
        var finishedAt: Date?
        /// Current step, e.g. "Pour to 150 g".
        var stepTitle: String
        /// SF Symbol of the current step.
        var stepSymbol: String
        /// What comes next, e.g. "Pour to 250 g" or "Done".
        var nextLabel: String?
        /// When the next step starts (shown as a countdown).
        var nextDate: Date?
        /// Live weight in grams, nil without a scale.
        var weight: Double?
        /// Cumulative target of the current pour.
        var pourTarget: Double?
        /// Target of the previous pour, so the progress bar shows this pour only.
        var pourBase: Double
    }

    var recipeName: String
    /// Total water of the recipe in grams.
    var water: Double
}
