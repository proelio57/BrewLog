import SwiftUI

/// Scale · GaggiMate · pressure at a glance: state and live value. Tapping one opens its setup.
/// The pressure comes from GaggiMate when it measures it, otherwise from the BOOKOO pressure sensor.
struct DeviceStrip: View {
    var onOpenSettings: () -> Void

    @Environment(ScaleManager.self) private var scale
    @Environment(MachineManager.self) private var machine
    @Environment(PressureMonitor.self) private var monitor
    @State private var showScale = false
    @State private var showSensor = false

    var body: some View {
        HStack(spacing: 8) {
            device("Scale", symbol: "scalemass.fill", live: scale.isReady,
                   value: scale.isReady ? scale.weight.grams1 : "Connect") { showScale = true }
            device("GaggiMate", symbol: "cup.and.saucer.fill", live: machine.isConnected,
                   value: machineValue, action: onOpenSettings)
            if machine.readsPressure {
                // GaggiMate measures the pressure itself: show its reading, no separate sensor.
                let pressure = machine.isConnected ? machine.status.pressure : nil
                device("Pressure", symbol: "gauge.with.dots.needle.67percent", live: pressure != nil,
                       value: pressure.map { String(format: "%.1f bar", $0) } ?? "–", action: onOpenSettings)
            } else {
                device("Pressure", symbol: "gauge.with.dots.needle.67percent", live: monitor.isReady,
                       value: monitor.isReady ? String(format: "%.1f bar", monitor.pressure)
                           : (monitor.isEnabled ? monitor.state.label : "Off")) { showSensor = true }
            }
        }
        .sheet(isPresented: $showScale) { ScaleConnectSheet() }
        .sheet(isPresented: $showSensor) { PressureMonitorSheet() }
    }

    private var machineValue: String {
        switch machine.state {
        case .off: return machine.kind == .none ? "Set up" : "Off"
        case .connecting: return "Connecting"
        case .unreachable: return "Offline"
        case .connected: return machine.status.temperature.map { String(format: "%.0f °C", $0) } ?? "Connected"
        }
    }

    private func device(_ name: String, symbol: String, live: Bool, value: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: symbol).font(.caption)
                    Circle().fill(live ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                }
                .foregroundStyle(live ? Color.accentColor : Color.secondary)
                Text(name).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
