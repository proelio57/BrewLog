import SwiftUI

/// The live numbers of an espresso shot: time and weight big, the flow below them, then ratio, pressure,
/// temperature, first drops. With Settings → Pressure view the pressure gets this place: `PressureFocusReadouts`.
struct ShotReadouts: View {
    let session: BrewSession
    @Environment(MachineManager.self) private var machine
    @Environment(PressureMonitor.self) private var monitor

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom) {
                big("TIME", session.elapsed.mmss, detail: "target \(session.recipe.targetTime.mmss)",
                    detailColor: session.isPastTargetTime && session.phase == .brewing ? .orange : .secondary)
                Spacer()
                big("WEIGHT", session.usesScale ? max(session.weight, 0).scaleReadout : "–",
                    detail: session.usesScale ? "of \(session.recipe.water.grams)" : "no scale", alignment: .trailing)
            }
            if session.usesScale { flow }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                tile("Ratio", session.liveRatio.map { String(format: "1:%.1f", $0) } ?? "–")
                if session.hasPressure {
                    tile("Pressure", livePressure.map { String(format: "%.1f bar", $0) } ?? "–",
                         detail: session.peakPressure > 0 ? String(format: "peak %.1f", session.peakPressure) : nil,
                         color: PressureFocus.zone(pressure: livePressure, target: session.recipe.pressure).color)
                }
                if machine.isConnected {
                    tile("Temp", liveTemperature.map { String(format: "%.1f °C", $0) } ?? "–")
                }
                tile("First drops", session.firstDropsTime.map { "\(Int($0.rounded())) s" } ?? "–")
            }
        }
    }

    private var livePressure: Double? { liveShotPressure(session: session, machine: machine, monitor: monitor) }

    /// The flow big and in the flow colour of the charts, with the recipe's target range.
    private var flow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("FLOW").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(String(format: "%.1f", max(session.flowRate, 0)))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.teal)
            Text("g/s").font(.headline).foregroundStyle(.teal)
            Spacer()
            if session.recipe.flowMax > 0 {
                Text(String(format: "target %g–%g g/s", session.recipe.flowMin, session.recipe.flowMax))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "Flow %.1f grams per second", max(session.flowRate, 0)))
    }

    private var liveTemperature: Double? {
        session.currentTemperature ?? (machine.isConnected ? machine.status.temperature : nil)
    }

    private func big(_ title: String, _ value: String, detail: String, detailColor: Color = .secondary,
                     alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 54, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(detail).font(.caption).foregroundStyle(detailColor).monospacedDigit()
        }
    }

    private func tile(_ title: String, _ value: String, detail: String? = nil, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color).monospacedDigit()
            Text(detail ?? " ").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Shown when the yield is (almost) reached and the app can't stop the machine itself.
struct StopNowBanner: View {
    var body: some View {
        Label("Stop now — target yield reached", systemImage: "hand.raised.fill")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.orange, in: RoundedRectangle(cornerRadius: 14))
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
