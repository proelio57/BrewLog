import ActivityKit
import Foundation

/// Shows a running brew on the Lock Screen and in the Dynamic Island, so you can leave the app while brewing.
/// The widget counts the timer itself. The app only sends new content when the step changes,
/// and the weight at most about once per second.
final class BrewLiveActivity {
    typealias State = BrewActivityAttributes.ContentState

    private var activity: Activity<BrewActivityAttributes>?
    private var lastState: State?
    private var lastUpdate = Date.distantPast

    var isRunning: Bool { activity != nil }

    func start(recipe: Recipe, state: State) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = BrewActivityAttributes(recipeName: recipe.name, water: recipe.water)
        activity = try? Activity.request(attributes: attributes,
                                         content: ActivityContent(state: state, staleDate: nil),
                                         pushType: nil)
        lastState = state
        lastUpdate = Date()
    }

    func update(_ state: State) {
        guard let activity, state != lastState else { return }
        let stepChanged = state.stepTitle != lastState?.stepTitle || state.nextDate != lastState?.nextDate
        guard stepChanged || Date().timeIntervalSince(lastUpdate) >= 1 else { return }
        lastState = state
        lastUpdate = Date()
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Ends the activity. A finished brew stays visible for a moment, a discarded one disappears right away.
    func end(_ state: State?, keepFor seconds: TimeInterval = 0) {
        guard let activity else { return }
        self.activity = nil
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = seconds > 0 ? .after(Date().addingTimeInterval(seconds)) : .immediate
        Task { await activity.end(content, dismissalPolicy: policy) }
    }

    /// Removes activities left over from a brew that never finished (e.g. the app was closed while brewing).
    static func endAll() {
        Task {
            for activity in Activity<BrewActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
