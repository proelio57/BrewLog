import SwiftUI

/// Dose, yield, ratio and the milk for espresso. The machine's temperature, pressure and profile are on the machine
/// card above; without a connected machine the brew temperature is set here.
struct EspressoSetupView: View {
    @Environment(BrewSetup.self) private var setup
    @Environment(MachineManager.self) private var machine

    /// The machine's target temperature when it is connected and plausible.
    static func machineTemperature(_ machine: MachineManager) -> Double? {
        guard machine.isConnected, let target = machine.status.targetTemperature, (70...105).contains(target) else { return nil }
        return target
    }

    var body: some View {
        @Bindable var setup = setup
        let recipe = setup.scaledRecipe
        return Card {
            VStack(spacing: 14) {
                HStack {
                    StatView(value: setup.dose.grams1, label: "Dose", symbol: "circle.grid.3x3.fill")
                    StatView(value: recipe.water.grams, label: "Yield", symbol: "drop.fill")
                    StatView(value: recipe.ratioText, label: "Ratio")
                    if setup.milk > 0 {
                        StatView(value: setup.milk.grams, label: "Milk", symbol: "drop.halffull")
                    }
                    if !machine.isConnected {
                        StatView(value: "\(Int(setup.waterTemp))°", label: "Temp", symbol: "thermometer.medium")
                    }
                }
                Divider()
                Stepper(value: $setup.dose, in: 5...30, step: 0.5) {
                    Label("Dose", systemImage: "scalemass")
                }
                // Milk drink: after the shot the machine switches to steam and BrewLog weighs the milk.
                Toggle(isOn: Binding(get: { setup.milk > 0 },
                                     set: { setup.milk = $0 ? (setup.recipe.milk ?? MilkStep.defaultMilk) : 0 })) {
                    Label("Milk drink", systemImage: "drop.halffull")
                }
                if setup.milk > 0 {
                    Stepper(value: $setup.milk, in: 20...500, step: 10) {
                        Label("Milk \(setup.milk.grams)", systemImage: "scalemass")
                    }
                }
                if !machine.isConnected {
                    Stepper(value: $setup.waterTemp, in: 70...100, step: 1) {
                        Label("Brew temperature", systemImage: "thermometer.medium")
                    }
                }
            }
        }
    }
}
