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

/// Power button for the machine card: switch on (plug + brew mode) or off (standby + plug).
struct MachinePowerButton: View {
    let power: MachinePower

    var body: some View {
        if power.canSwitchOff {
            Button { power.switchOff() } label: {
                Label("Off", systemImage: "power")
            }
            .tint(.secondary)
            .accessibilityLabel("Switch the machine off")
        } else if power.canSwitchOn {
            Button { power.switchOn() } label: {
                Label("On", systemImage: "power")
            }
            .tint(.green)
            .accessibilityLabel("Switch the machine on")
        }
    }
}
