import SwiftUI

/// The live pressure of a shot: while the shot runs the session's reading; before that the machine's, or the
/// sensor's for machines BrewLog can't connect to.
func liveShotPressure(session: BrewSession, machine: MachineManager, monitor: PressureMonitor) -> Double? {
    if session.phase == .brewing, let current = session.currentPressure { return current }
    if machine.readsPressure { return machine.isConnected ? machine.status.pressure : nil }
    return monitor.isReady ? monitor.pressure : nil
}

extension PressureZone {
    var color: Color {
        switch self {
        case .low: return .blue
        case .onTarget: return .green
        case .high: return .red
        case .noTarget: return .accentColor
        }
    }
}

/// Shot readouts when the screen is about the pressure (Settings → Pressure view): the bar number big and
/// coloured by how far it is from the recipe's target, so the pressure can be set by hand.
struct PressureFocusReadouts: View {
    let session: BrewSession
    @Environment(MachineManager.self) private var machine
    @Environment(PressureMonitor.self) private var monitor

    var body: some View {
        let pressure = liveShotPressure(session: session, machine: machine, monitor: monitor)
        let target = session.recipe.pressure
        let zone = PressureFocus.zone(pressure: pressure, target: target)
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                compact("TIME", session.elapsed.mmss,
                        color: session.isPastTargetTime && session.phase == .brewing ? .orange : .primary)
                Spacer()
                compact("WEIGHT", session.usesScale ? max(session.weight, 0).scaleReadout + " g" : "–", alignment: .trailing)
            }
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(pressure.map { String(format: "%.1f", max($0, 0)) } ?? "–")
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("bar").font(.title2.weight(.semibold))
                }
                .foregroundStyle(zone.color)
                Text(caption(pressure: pressure, target: target, zone: zone))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(zone == .noTarget ? Color.secondary : zone.color)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(zone.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibility(pressure: pressure, zone: zone))
            HStack(spacing: 8) {
                if session.usesScale {
                    tile("Flow", String(format: "%.1f g/s", max(session.flowRate, 0)), color: .teal)
                }
                tile("Ratio", session.liveRatio.map { String(format: "1:%.1f", $0) } ?? "–")
                if machine.isConnected, let temperature = session.currentTemperature ?? machine.status.temperature {
                    tile("Temp", String(format: "%.1f °C", temperature))
                }
                tile("First drops", session.firstDropsTime.map { "\(Int($0.rounded())) s" } ?? "–")
            }
        }
    }

    private func caption(pressure: Double?, target: Double?, zone: PressureZone) -> String {
        guard let target, let pressure else {
            return session.peakPressure > 0 ? String(format: "peak %.1f bar", session.peakPressure) : " "
        }
        let delta = abs(pressure - target)
        switch zone {
        case .low: return String(format: "target %.1f bar · %.1f low", target, delta)
        case .high: return String(format: "target %.1f bar · %.1f high", target, delta)
        case .onTarget, .noTarget: return String(format: "target %.1f bar · on target", target)
        }
    }

    private func accessibility(pressure: Double?, zone: PressureZone) -> String {
        guard let pressure else { return "Pressure unknown" }
        let state: String
        switch zone {
        case .low: state = ", below target"
        case .onTarget: state = ", on target"
        case .high: state = ", above target"
        case .noTarget: state = ""
        }
        return String(format: "Pressure %.1f bar", pressure) + state
    }

    private func compact(_ title: String, _ value: String, color: Color = .primary,
                         alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private func tile(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
