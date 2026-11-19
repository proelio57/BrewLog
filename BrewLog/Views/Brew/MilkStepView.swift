import SwiftUI

/// Values for the milk step of a milk drink (Recipe.milk).
enum MilkStep {
    /// Milk when "Milk drink" is switched on for a recipe without a milk amount.
    static let defaultMilk = 150.0

    /// 0…1 towards the target, for the progress bar.
    static func progress(weight: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(max(weight / target, 0), 1)
    }

    /// The weight to keep: nothing (nil) below 1 g, so skipping or never pouring leaves no milk on the brew.
    static func recorded(_ weight: Double) -> Double? {
        weight >= 1 ? (weight * 10).rounded() / 10 : nil
    }
}

/// After the shot of a milk drink: pitcher on the scale, tare, pour the milk to the recipe's amount while the
/// machine heats up for steam. Then on to rating the shot.
struct MilkStepView: View {
    let target: Double
    /// The machine was switched to steam.
    let steaming: Bool
    var onDone: (Double?) -> Void

    @Environment(ScaleManager.self) private var scale
    @Environment(MachineManager.self) private var machine

    /// The phone's scale, or the one connected to GaggiMate.
    private var weight: Double? {
        if scale.isReady { return scale.weight }
        if machine.isConnected, machine.status.hasWeight { return machine.status.weight }
        return nil
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Label("Weigh the milk", systemImage: "drop.halffull")
                .font(.title2.weight(.semibold))
            Text("Pitcher on the scale, tare, then pour to \(target.grams).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let weight {
                Text(weight.grams)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                ProgressView(value: MilkStep.progress(weight: weight, target: target))
                    .tint(weight >= target - 2 ? .green : .accentColor)
                    .padding(.horizontal, 32)
                Button {
                    if scale.isReady { scale.tare() } else { machine.tareScale() }
                    Haptics.tap()
                } label: {
                    Label("Tare", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            } else {
                Text("No scale connected. Pour \(target.grams) of milk.")
                    .foregroundStyle(.secondary)
            }

            if steaming { steamStatus }
            Spacer()
            Button {
                onDone(weight.flatMap(MilkStep.recorded))
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Skip") { onDone(nil) }
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    @ViewBuilder
    private var steamStatus: some View {
        let status = machine.status
        if let temperature = status.temperature, let steamTarget = status.targetTemperature, steamTarget > 0 {
            let ready = temperature >= steamTarget - 2
            Label(ready ? "Steam ready" : String(format: "Steam heating · %.0f / %.0f °C", temperature, steamTarget),
                  systemImage: ready ? "checkmark.circle.fill" : "flame")
                .foregroundStyle(ready ? .green : .orange)
                .font(.subheadline.weight(.medium))
        } else {
            Label("Steam heating", systemImage: "flame")
                .foregroundStyle(.orange)
                .font(.subheadline.weight(.medium))
        }
    }
}
