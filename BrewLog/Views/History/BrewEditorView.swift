import SwiftUI
import SwiftData

/// Corrects a saved brew: date, recipe, amounts, time, temperature, grind and gear.
/// Edits go to a draft and are only written on Save. The analysis is recalculated from the new values.
struct BrewEditorView: View {
    let brew: Brew

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    @Query(sort: \SavedRecipe.createdAt, order: .reverse) private var saved: [SavedRecipe]

    @State private var date: Date
    @State private var recipeID: String
    @State private var dose: Double
    @State private var finalWeight: Double
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var waterTemp: Double
    @State private var brewerID: UUID?
    @State private var grinderID: UUID?
    @State private var filterID: UUID?
    @State private var waterID: UUID?
    /// The grind on the grinder's scale (a grinder is chosen) or as free text (none).
    @State private var grindValue: Double?
    @State private var grindText: String
    @FocusState private var focused: Bool

    init(brew: Brew) {
        self.brew = brew
        _date = State(initialValue: brew.date)
        _recipeID = State(initialValue: brew.recipe == nil ? "" : brew.recipeID)
        _dose = State(initialValue: brew.dose)
        _finalWeight = State(initialValue: brew.finalWeight)
        let total = Int(brew.totalTime.rounded())
        _minutes = State(initialValue: total / 60)
        _seconds = State(initialValue: total % 60)
        _waterTemp = State(initialValue: brew.waterTemp)
        _brewerID = State(initialValue: brew.brewerID)
        _grinderID = State(initialValue: brew.grinderID)
        _filterID = State(initialValue: brew.filterID)
        _waterID = State(initialValue: brew.waterID)
        _grindValue = State(initialValue: brew.grindValue)
        _grindText = State(initialValue: brew.grindSetting)
    }

    /// The scale of the chosen grinder (its own, or the one stored with the brew while that grinder is unchanged).
    private var grinderSpec: GrinderSpec? {
        if let grinder = equipment.first(where: { $0.id == grinderID && $0.type == .grinder }) { return grinder.grinderSpec }
        return grinderID != nil && grinderID == brew.grinderID ? brew.grinderSpec : nil
    }

    private var recipes: [Recipe] { saved.compactMap(\.recipe) + RecipeLibrary.presets }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $date, in: ...Date())
                Picker("Recipe", selection: $recipeID) {
                    if brew.recipe == nil {
                        Text(brew.recipeName.isEmpty ? "None" : "\(brew.recipeName) (no recipe)").tag("")
                    } else if !recipes.contains(where: { $0.id == brew.recipeID }) {
                        Text(brew.recipeName).tag(brew.recipeID)
                    }
                    ForEach(recipes) { Text($0.name).tag($0.id) }
                }
            } footer: {
                Text("Choosing a recipe for a brew without one, for example an imported brew, enables the analysis.")
            }

            Section("Amounts") {
                numberRow("Coffee", unit: "g", value: $dose)
                numberRow("Water in the cup", unit: "g", value: $finalWeight)
                numberRow("Temperature", unit: "°C", value: $waterTemp)
                HStack {
                    Text("Total time")
                    Spacer()
                    TextField("m", value: $minutes, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 44)
                        .focused($focused)
                    Text(":")
                    TextField("ss", value: $seconds, format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 44)
                        .focused($focused)
                }
            }

            Section("Grind") {
                gearPicker("Grinder", symbol: "gearshape.2.fill", type: .grinder, current: brew.grinderName, selection: $grinderID)
                grindRow
            }

            Section("Gear") {
                gearPicker(brew.isEspresso ? "Machine" : "Brewer", symbol: "cup.and.saucer.fill", type: .brewer,
                           current: brew.brewerName, selection: $brewerID)
                if !brew.isEspresso {
                    gearPicker("Filter", symbol: "doc.fill", type: .filter, current: brew.filterName, selection: $filterID)
                }
                gearPicker("Water", symbol: "drop.triangle.fill", type: .water, current: brew.waterName, selection: $waterID)
            }
        }
        .navigationTitle("Edit brew")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private func numberRow(_ title: String, unit: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused($focused)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    /// The grind size: a number on the grinder's scale with finer/coarser steps, or free text without a grinder.
    @ViewBuilder
    private var grindRow: some View {
        if let spec = grinderSpec {
            HStack {
                Label("Grind size", systemImage: "dial.medium")
                Spacer()
                TextField("–", value: $grindValue, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .focused($focused)
                    .accessibilityIdentifier("brew.grind")
                Text(spec.unit.suffix.isEmpty ? spec.unit.displayName.lowercased() : spec.unit.suffix)
                    .foregroundStyle(.secondary)
                Stepper("Grind size", onIncrement: { nudgeGrind(spec, by: spec.step) },
                        onDecrement: { nudgeGrind(spec, by: -spec.step) })
                    .labelsHidden()
            }
        } else {
            HStack {
                Label("Grind size", systemImage: "dial.medium")
                Spacer()
                TextField("e.g. medium-fine", text: $grindText)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
            }
        }
    }

    private func nudgeGrind(_ spec: GrinderSpec, by delta: Double) {
        grindValue = max(0, (((grindValue ?? 0) + delta) / spec.step).rounded() * spec.step)
    }

    /// A gear menu with its label. A deleted item stays selectable under its old name until something else is picked.
    private func gearPicker(_ title: String, symbol: String, type: EquipmentType, current: String,
                            selection: Binding<UUID?>) -> some View {
        var options = equipment.filter { $0.type == type }.map { PickerOption(id: $0.id, name: $0.name) }
        if let id = selection.wrappedValue, !options.contains(where: { $0.id == id }), !current.isEmpty {
            options.insert(PickerOption(id: id, name: current), at: 0)
        }
        return Picker(selection: selection) {
            Text("None").tag(UUID?.none)
            ForEach(options) { Text($0.name).tag(Optional($0.id)) }
        } label: {
            Label(title, systemImage: symbol)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("picker.\(title)")
    }

    private func save() {
        let newDose = dose.clamped(0, InputLimits.maxDose)
        let oldDose = brew.dose

        brew.date = min(date, Date())
        brew.finalWeight = finalWeight.clamped(0, InputLimits.maxWater)
        brew.waterTemp = waterTemp.clamped(0, 100)
        brew.totalTime = Double(max(minutes, 0) * 60 + max(seconds, 0)).clamped(0, InputLimits.maxBrewSeconds)

        if recipeID != (brew.recipe == nil ? "" : brew.recipeID), let recipe = recipes.first(where: { $0.id == recipeID }) {
            // Another recipe: store it scaled to this brew's dose, like a brew started from it.
            let scaled = recipe.scaled(toDose: newDose > 0 ? newDose : recipe.dose)
            brew.recipeID = recipe.id
            brew.recipeName = recipe.name
            brew.recipe = scaled
            brew.targetWater = scaled.water
        } else if newDose != oldDose, newDose > 0, let recipe = brew.recipe {
            // Same recipe, corrected dose: keep the recipe in step so ratio and pour targets still match.
            let scaled = recipe.scaled(toDose: newDose)
            brew.recipe = scaled
            brew.targetWater = scaled.water
        }

        if newDose != oldDose, let bean = brew.bean {
            bean.remaining = (bean.remaining - (newDose - oldDose)).clamped(0, InputLimits.maxBagWeight)
        }
        brew.dose = newDose

        if brewerID != brew.brewerID {
            let brewer = equipment.first { $0.id == brewerID }
            brew.brewerID = brewer?.id
            brew.brewerName = brewer?.name ?? ""
        }
        if grinderID != brew.grinderID {
            brew.setGrinder(equipment.first { $0.id == grinderID })
        }
        if filterID != brew.filterID {
            brew.setFilter(equipment.first { $0.id == filterID })
        }
        if waterID != brew.waterID {
            brew.setWater(equipment.first { $0.id == waterID })
        }
        // The grind: on the grinder's scale, or free text when there is no grinder.
        if grinderSpec != nil {
            brew.grindValue = grindValue.map { $0.clamped(0, 10_000) }
        } else {
            brew.grindValue = nil
            brew.grindSetting = String(grindText.prefix(120))
        }

        try? context.save()
        dismiss()
    }
}
