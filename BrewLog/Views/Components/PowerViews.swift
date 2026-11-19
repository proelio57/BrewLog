import SwiftUI

/// Over every tab: the countdown before the smart plug goes off (with Cancel), and "ready" after switching on.
struct PowerBanner: View {
    let power: MachinePower

    var body: some View {
        Group {
            if let seconds = power.secondsLeft {
                HStack(spacing: 12) {
                    Image(systemName: "powerplug")
                    Text("Plug off in \(seconds) s").monospacedDigit()
                    Button("Cancel") { power.cancelCountdown() }
                        .fontWeight(.semibold)
                }
            } else if let message = power.readyMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4, y: 2)
        .padding(.top, 4)
        .opacity(power.secondsLeft != nil || power.readyMessage != nil ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: power.secondsLeft != nil || power.readyMessage != nil)
        .accessibilityElement(children: .contain)
    }
}

/// Power switch for the machine card. Shows the smart plug's state (or the machine's, without a plug) and switches
/// it the other way: Off (grey) → tap to switch on; Starting/Heating (orange); On (green) → tap to switch off.
struct MachinePowerButton: View {
    let power: MachinePower

    var body: some View {
        switch power.buttonState {
        case .off: button("Off", tint: .secondary, hint: "Switches the machine on")
        case .starting: button("Starting", tint: .orange, hint: "Switches the machine off")
        case .heating: button("Heating", tint: .orange, hint: "Switches the machine off")
        case .on: button("On", tint: .green, hint: "Switches the machine off")
        case nil: EmptyView()
        }
    }

    private func button(_ title: String, tint: Color, hint: String) -> some View {
        Button { power.pressButton() } label: {
            Label(title, systemImage: "power")
        }
        .tint(tint)
        .accessibilityLabel("Machine \(title.lowercased())")
        .accessibilityHint(hint)
    }
}

/// Flush the group head (GaggiMate, demo): before the shot to bring the group to temperature and clear old coffee,
/// after it to rinse the screen. Tapping again stops a running flush.
struct FlushButton: View {
    @Environment(MachineManager.self) private var machine

    var body: some View {
        if machine.canFlush {
            Button {
                machine.toggleFlush()
                Haptics.tap()
            } label: {
                Label(machine.isFlushing ? "Flushing… tap to stop" : "Flush",
                      systemImage: machine.isFlushing ? "stop.circle" : "drop.triangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(machine.isFlushing ? .orange : .accentColor)
            .accessibilityHint("Runs water through the group head")
        }
    }
}
