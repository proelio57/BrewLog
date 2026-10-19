import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BrewLogWidgets: WidgetBundle {
    var body: some Widget {
        BrewLiveActivityWidget()
        BrewLogStatusWidget()
        BrewLogQuickWidget()
    }
}

/// The app's accent colour (the extension has no asset catalog).
private let brand = Color(red: 0.722, green: 0.427, blue: 0.235)

struct BrewLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BrewActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activitySystemActionForegroundColor(brand)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.recipeName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        BrewTimer(state: state)
                            .font(.title2.weight(.semibold))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let weight = state.weight {
                        WeightText(weight: weight, target: state.pourTarget)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        StepRow(state: state)
                        PourProgress(state: state)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: state.stepSymbol).foregroundStyle(brand)
            } compactTrailing: {
                if let weight = state.weight, state.finishedAt == nil {
                    Text("\(Int(weight)) g").monospacedDigit().foregroundStyle(brand)
                } else {
                    BrewTimer(state: state)
                        .frame(maxWidth: 48)
                        .foregroundStyle(brand)
                }
            } minimal: {
                Image(systemName: state.stepSymbol).foregroundStyle(brand)
            }
            .keylineTint(brand)
        }
    }
}

private struct LockScreenView: View {
    let attributes: BrewActivityAttributes
    let state: BrewActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Label(attributes.recipeName, systemImage: "drop.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(brand)
                        .lineLimit(1)
                    BrewTimer(state: state)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                }
                Spacer()
                if let weight = state.weight {
                    WeightText(weight: weight, target: state.pourTarget)
                }
            }
            StepRow(state: state)
            PourProgress(state: state)
        }
    }
}

/// Elapsed brew time. Counts by itself, so the app doesn't have to update every second.
private struct BrewTimer: View {
    let state: BrewActivityAttributes.ContentState

    var body: some View {
        Group {
            if let finishedAt = state.finishedAt, finishedAt >= state.startDate {
                Text(timerInterval: state.startDate...finishedAt, pauseTime: finishedAt, countsDown: false)
            } else {
                Text(timerInterval: state.startDate...Date.distantFuture, countsDown: false)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.leading)
    }
}

private struct WeightText: View {
    let weight: Double
    let target: Double?

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(Int(weight)) g")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            if let target {
                Text("of \(Int(target)) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct StepRow: View {
    let state: BrewActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            Label(state.stepTitle, systemImage: state.stepSymbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let label = state.nextLabel, let date = state.nextDate, date > Date() {
                HStack(spacing: 4) {
                    Text(label).lineLimit(1)
                    Text(timerInterval: Date()...date, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PourProgress: View {
    let state: BrewActivityAttributes.ContentState

    var body: some View {
        if let weight = state.weight, let target = state.pourTarget, target > state.pourBase {
            ProgressView(value: min(max(weight - state.pourBase, 0), target - state.pourBase),
                         total: target - state.pourBase)
                .tint(weight > target + 2 ? .orange : brand)
        }
    }
}
