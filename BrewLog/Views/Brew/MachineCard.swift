import SwiftUI

/// Espresso machine, its state and the scale in one card at the top of the Brew tab (espresso): power, connection,
/// boiler and target temperature, pressure, profile, mode, temperature nudge, and the scale's weight with Tare.
/// The gear opens the machine settings.
struct MachineCard: View {
    var onOpenSettings: () -> Void

    @Environment(MachineManager.self) private var machine
    @Environment(ScaleManager.self) private var scale
    @State private var showProfiles = false
    @State private var showScale = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label(machine.kind == .none ? "Machine" : machine.displayName, systemImage: "cup.and.saucer.fill")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    MachinePowerButton(power: MachinePower.shared)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    if machine.kind != .none { stateBadge }
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Machine settings")
                }
                if machine.kind == .none {
                    Text("Connect a GaggiMate (Wi-Fi), a Decent DE1 (Bluetooth) or a La Marzocco (your La Marzocco account) to record pressure, temperature and flow and start shots from here. Without one, BrewLog times the shot with your scale.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Set up machine", action: onOpenSettings)
                        .font(.subheadline.weight(.semibold))
                } else if machine.isConnected {
                    connectedControls
                } else {
                    Text(unreachableText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !machine.readsPressure {
                    PressureMonitorRow()
                        .font(.subheadline)
                }
                Divider()
                scaleRow
            }
        }
        // On the card, not on the profile button: the sheet stays open (and shows the error) if the machine drops.
        .sheet(isPresented: $showProfiles) { MachineProfilesSheet() }
        .sheet(isPresented: $showScale) { ScaleConnectSheet() }
    }

    /// The phone's scale, or the one connected to GaggiMate.
    @ViewBuilder
    private var scaleRow: some View {
        let machineWeight = machine.isConnected && machine.status.hasWeight ? machine.status.weight : nil
        HStack {
            Button { showScale = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "scalemass.fill")
                    Circle().fill(scale.isReady || machineWeight != nil ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                    if scale.isReady {
                        Text(scale.weight.grams1).monospacedDigit().fontWeight(.semibold)
                    } else if let machineWeight {
                        Text(machineWeight.grams1).monospacedDigit().fontWeight(.semibold)
                        Text("via \(machine.displayName)").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Connect scale").foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if scale.isReady {
                TareChip { scale.tare() }
            } else if machineWeight != nil {
                TareChip { machine.tareScale() }
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var connectedControls: some View {
        let status = machine.status
        HStack(spacing: 16) {
            if machine.kind == .laMarzocco {
                // The cloud has no live temperature or profiles: the boiler's state and target instead.
                StatView(value: boilerText(status.systemState), label: "Boiler", symbol: "thermometer.medium")
                StatView(value: status.targetTemperature.map { String(format: "%.1f°", $0) } ?? "–", label: "Target")
            } else {
                StatView(value: status.temperature.map { String(format: "%.1f°", $0) } ?? "–", label: "Boiler",
                         symbol: "thermometer.medium")
                StatView(value: status.targetTemperature.map { String(format: "%.0f°", $0) } ?? "–", label: "Target")
                if machine.readsPressure {
                    StatView(value: status.pressure.map { String(format: "%.1f", $0) } ?? "–", label: "bar",
                             symbol: "gauge.with.dots.needle.67percent")
                }
            }
        }
        if machine.kind != .laMarzocco {
            if machine.canChooseProfile {
                Button { showProfiles = true } label: {
                    HStack {
                        Label("Profile", systemImage: "slider.horizontal.3").foregroundStyle(.secondary)
                        Spacer()
                        Text(status.profile ?? "–").fontWeight(.semibold).lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Choose the profile on the machine")
            } else if let profile = status.profile {
                LabeledContent("Profile", value: profile).font(.subheadline)
            }
        }
        if machine.kind.capabilities.contains(.startStop) {
            Picker("Mode", selection: Binding(get: { MachineMode(rawValue: status.mode ?? 0) ?? .standby },
                                              set: { machine.setMode($0) })) {
                ForEach(MachineMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            FlushButton()
        } else if machine.kind.capabilities.contains(.power) {
            Toggle(isOn: Binding(get: { status.mode == MachineMode.brew.rawValue },
                                 set: { machine.setPower($0) })) {
                Label("Machine on", systemImage: "power")
            }
            .font(.subheadline)
        }
        if machine.kind.capabilities.contains(.temperatureNudge) {
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

    private func boilerText(_ state: String?) -> String {
        switch state {
        case "ready": return "Ready"
        case "heating": return "Heating"
        case "standby": return "Off"
        case "error": return "Check"
        default: return "–"
        }
    }

    private var unreachableText: String {
        if machine.kind == .laMarzocco {
            if !machine.laMarzocco.isReady { return "Sign in to your La Marzocco account in the machine settings." }
            return machine.state == .connecting ? "Connecting to La Marzocco…"
                : (machine.notice ?? "Can't reach the machine through La Marzocco right now.")
        }
        if machine.kind == .decent {
            if !machine.decent.hasSavedMachine { return "Pair your DE1 in the machine settings." }
            return machine.state == .connecting ? "Connecting to the DE1 over Bluetooth…"
                : "Can't reach the DE1. Is it on and nearby?"
        }
        return machine.state == .connecting ? "Connecting to \(machine.host)…"
            : "Can't reach \(machine.host). Is the machine on and in the same Wi-Fi?"
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
