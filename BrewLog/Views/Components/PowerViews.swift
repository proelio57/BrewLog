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

/// Power switch for the machine card. Shows the machine's state and switches it the other way:
/// Off (grey) → tap to switch on; Starting (orange) while it comes up and heats; On (green) → tap to switch off.
struct MachinePowerButton: View {
    let power: MachinePower

    var body: some View {
        if power.canSwitchOff {
            if power.starting {
                button("Heating", tint: .orange, hint: "Switches the machine off") { power.switchOff() }
            } else {
                button("On", tint: .green, hint: "Switches the machine off") { power.switchOff() }
            }
        } else if power.starting {
            button("Starting", tint: .orange, hint: "Switches the machine off") { power.switchOff() }
        } else if power.canSwitchOn {
            button("Off", tint: .secondary, hint: "Switches the machine on") { power.switchOn() }
        }
    }

    private func button(_ title: String, tint: Color, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "power")
        }
        .tint(tint)
        .accessibilityLabel("Machine \(title.lowercased())")
        .accessibilityHint(hint)
    }
}
