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
                Stepper(value: $setup.dose, in: 5...30, step: 0.5) {
                    ValueLabel(title: "Dose", value: setup.dose.grams1, symbol: "scalemass")
                }
                ValueLabel(title: "Yield", value: "\(recipe.water.grams) · \(recipe.ratioText)", symbol: "drop.fill")
                    .padding(.trailing, 4)
                // Milk drink: after the shot the machine switches to steam and BrewLog weighs the milk.
                Toggle(isOn: Binding(get: { setup.milk > 0 },
                                     set: { setup.milk = $0 ? (setup.recipe.milk ?? MilkStep.defaultMilk) : 0 })) {
                    Label("Milk drink", systemImage: "drop.halffull")
                }
                if setup.milk > 0 {
                    Stepper(value: $setup.milk, in: 20...500, step: 10) {
                        ValueLabel(title: "Milk", value: setup.milk.grams, symbol: "scalemass")
                    }
                }
                if !machine.isConnected {
                    Stepper(value: $setup.waterTemp, in: 70...100, step: 1) {
                        ValueLabel(title: "Temperature", value: "\(Int(setup.waterTemp)) °C", symbol: "thermometer.medium")
                    }
                }
            }
        }
    }
}
