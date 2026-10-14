import SwiftUI
import SwiftData

/// Corrects a saved brew: date, recipe, amounts, time, temperature and gear.
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
                numberRow("Water", unit: "g", value: $finalWeight)
                numberRow("Water temp", unit: "°C", value: $waterTemp)
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

            Section("Gear") {
                gearPicker("Brewer", symbol: "cup.and.saucer.fill", type: .brewer, current: brew.brewerName, selection: $brewerID)
                gearPicker("Grinder", symbol: "gearshape.2.fill", type: .grinder, current: brew.grinderName, selection: $grinderID)
                gearPicker("Filter", symbol: "doc.fill", type: .filter, current: brew.filterName, selection: $filterID)
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

    /// Gear picker. A deleted item stays selectable under its old name until something else is picked.
    private func gearPicker(_ title: String, symbol: String, type: EquipmentType, current: String,
                            selection: Binding<UUID?>) -> some View {
        var options = equipment.filter { $0.type == type }.map { PickerOption(id: $0.id, name: $0.name) }
        if let id = selection.wrappedValue, !options.contains(where: { $0.id == id }), !current.isEmpty {
            options.insert(PickerOption(id: id, name: current), at: 0)
        }
        return MenuPickerRow(title: title, symbol: symbol, options: options, selection: selection)
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

        try? context.save()
        dismiss()
    }
}
