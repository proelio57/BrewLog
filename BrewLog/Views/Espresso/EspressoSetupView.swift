import SwiftUI

/// Dose, yield and ratio for espresso. The machine's temperature, pressure and profile are on the machine
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
                if !machine.isConnected {
                    Stepper(value: $setup.waterTemp, in: 70...100, step: 1) {
                        ValueLabel(title: "Temperature", value: "\(Int(setup.waterTemp)) °C", symbol: "thermometer.medium")
                    }
                }
            }
        }
    }
}


/// Milk drink or plain espresso, right under the recipe at the top of the espresso Brew tab: after the shot the
/// machine switches to steam and BrewLog weighs the milk.
struct MilkDrinkCard: View {
    @Environment(BrewSetup.self) private var setup

    var body: some View {
        @Bindable var setup = setup
        return Card {
            VStack(spacing: 10) {
                Toggle(isOn: Binding(get: { setup.milk > 0 },
                                     set: { setup.milk = $0 ? (setup.recipe.milk ?? MilkStep.defaultMilk) : 0 })) {
                    Label("Milk drink", systemImage: "drop.halffull")
                }
                if setup.milk > 0 {
                    Stepper(value: $setup.milk, in: 20...500, step: 10) {
                        ValueLabel(title: "Milk", value: setup.milk.grams, symbol: "scalemass")
                    }
                }
            }
        }
    }
}
