import SwiftUI

/// Espresso machine status and controls on the Brew tab: mode, temperature, sending the recipe as a profile.
struct MachineCard: View {
    let recipe: Recipe
    let dose: Double
    let temperature: Double
    var onOpenSettings: () -> Void

    @Environment(MachineManager.self) private var machine

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(machine.displayName, systemImage: "cup.and.saucer.fill").font(.headline)
                    Spacer()
                    stateBadge
                }
                PressureMonitorRow()
                    .font(.subheadline)
                if machine.kind == .none {
                    Text("Connect a GaggiMate to record pressure and temperature, start shots from here and send recipes as profiles. Without one, BrewLog times the shot with your scale.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Set up machine", action: onOpenSettings)
                        .font(.subheadline.weight(.semibold))
                } else if machine.isConnected {
                    connectedControls
                } else {
                    Text(machine.state == .connecting ? "Connecting to \(machine.host)…"
                         : "Can't reach \(machine.host). Is the machine on and in the same Wi-Fi?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Machine settings", action: onOpenSettings)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var connectedControls: some View {
        let status = machine.status
        HStack(spacing: 16) {
            StatView(value: status.temperature.map { String(format: "%.1f°", $0) } ?? "–", label: "Boiler",
                     symbol: "thermometer.medium")
            StatView(value: status.targetTemperature.map { String(format: "%.0f°", $0) } ?? "–", label: "Target")
            StatView(value: status.profile ?? "–", label: "Profile")
        }
        Picker("Mode", selection: Binding(get: { MachineMode(rawValue: status.mode ?? 0) ?? .standby },
                                          set: { machine.setMode($0) })) {
            ForEach(MachineMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        HStack {
            Label("Temperature", systemImage: "thermometer.medium").foregroundStyle(.secondary)
            Spacer()
            Button { machine.nudgeTemperature(up: false) } label: { Image(systemName: "minus.circle.fill") }
                .accessibilityLabel("1 °C cooler")
            Button { machine.nudgeTemperature(up: true) } label: { Image(systemName: "plus.circle.fill") }
                .accessibilityLabel("1 °C hotter")
        }
        .font(.subheadline)
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        Button {
            machine.sendProfile(recipe: recipe, dose: dose, temperature: temperature)
        } label: {
            Label("Send recipe to machine", systemImage: "square.and.arrow.up.on.square")
                .font(.subheadline.weight(.semibold))
        }
        if let notice = machine.notice {
            Text(notice).font(.caption).foregroundStyle(.secondary)
        }
        if let message = status.systemMessage, !message.isEmpty {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var stateBadge: some View {
        let (text, color): (String, Color) = {
            switch machine.state {
            case .off: return ("Off", .secondary)
            case .connecting: return ("Connecting", .orange)
            case .connected: return (machine.status.isBrewing ? "Brewing" : "Connected", .green)
            case .unreachable: return ("Offline", .red)
            }
        }()
        return Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
