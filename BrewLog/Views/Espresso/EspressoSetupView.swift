import SwiftUI

/// Dose, yield, ratio and temperature for espresso. With a GaggiMate connected its settings win: target
/// temperature, target pressure and profile come from the machine ("from GaggiMate") and can't be changed here.
struct EspressoSetupView: View {
    @Environment(BrewSetup.self) private var setup
    @Environment(MachineManager.self) private var machine
    @State private var showProfiles = false

    /// The machine's target temperature when it is connected and plausible.
    static func machineTemperature(_ machine: MachineManager) -> Double? {
        guard machine.isConnected, let target = machine.status.targetTemperature, (70...105).contains(target) else { return nil }
        return target
    }

    var body: some View {
        @Bindable var setup = setup
        let recipe = setup.scaledRecipe
        let machineTemp = Self.machineTemperature(machine)
        let pressure = ShotMonitor.targetPressure(recipe: recipe.pressure,
                                                  machineTarget: machine.isConnected ? machine.status.targetPressure : nil)
        return Card {
            VStack(spacing: 14) {
                HStack {
                    StatView(value: setup.dose.grams1, label: "Dose", symbol: "circle.grid.3x3.fill")
                    StatView(value: recipe.water.grams, label: "Yield", symbol: "drop.fill")
                    StatView(value: recipe.ratioText, label: "Ratio")
                    StatView(value: "\(Int(machineTemp ?? setup.waterTemp))°", label: "Temp", symbol: "thermometer.medium")
                }
                Divider()
                Stepper(value: $setup.dose, in: 5...30, step: 0.5) {
                    Label("Dose", systemImage: "scalemass")
                }
                if machine.isConnected {
                    VStack(spacing: 8) {
                        machineRow("Temperature", machineTemp.map { String(format: "%.0f °C", $0) } ?? "–",
                                   symbol: "thermometer.medium")
                        machineRow("Pressure", pressure.map { String(format: "%.1f bar", $0) } ?? "–",
                                   symbol: "gauge.with.dots.needle.67percent")
                        if machine.canChooseProfile {
                            Button { showProfiles = true } label: {
                                HStack(spacing: 4) {
                                    machineRow("Profile", machine.status.profile ?? "–", symbol: "slider.horizontal.3")
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Choose the profile on the machine")
                            .sheet(isPresented: $showProfiles) { MachineProfilesSheet() }
                        } else {
                            machineRow("Profile", machine.status.profile ?? "–", symbol: "slider.horizontal.3")
                        }
                        Text("from \(machine.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    Stepper(value: $setup.waterTemp, in: 70...100, step: 1) {
                        Label("Brew temperature", systemImage: "thermometer.medium")
                    }
                }
                HStack {
                    Label("Grind", systemImage: "dial.medium").foregroundStyle(.secondary)
                    Spacer()
                    Text(setup.recipe.grind).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
            }
        }
    }

    private func machineRow(_ title: String, _ value: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit().lineLimit(1)
        }
        .font(.subheadline)
    }
}
