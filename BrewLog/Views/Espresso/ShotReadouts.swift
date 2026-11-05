import SwiftUI

/// The live numbers of an espresso shot: time and weight big, then ratio, flow, pressure, temperature, first drops.
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                tile("Ratio", session.liveRatio.map { String(format: "1:%.1f", $0) } ?? "–")
                if session.usesScale {
                    tile("Flow", String(format: "%.1f g/s", max(session.flowRate, 0)))
                }
                if session.hasPressure {
                    tile("Pressure", livePressure.map { String(format: "%.1f bar", $0) } ?? "–",
                         detail: session.peakPressure > 0 ? String(format: "peak %.1f", session.peakPressure) : nil)
                }
                if machine.isConnected {
                    tile("Temp", liveTemperature.map { String(format: "%.1f °C", $0) } ?? "–")
                }
                tile("First drops", session.firstDropsTime.map { "\(Int($0.rounded())) s" } ?? "–")
            }
        }
    }

    /// While the shot runs the session's reading; before that the machine's, or the sensor's for machines
    /// BrewLog can't connect to.
    private var livePressure: Double? {
        if session.phase == .brewing, let current = session.currentPressure { return current }
        if machine.readsPressure { return machine.isConnected ? machine.status.pressure : nil }
        return monitor.isReady ? monitor.pressure : nil
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

    private func tile(_ title: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
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
