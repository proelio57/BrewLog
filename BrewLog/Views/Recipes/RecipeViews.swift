import SwiftUI
import SwiftData

// MARK: - List

struct RecipeListView: View {
    @Query(sort: \SavedRecipe.createdAt, order: .reverse) private var saved: [SavedRecipe]
    @State private var newRecipe: Recipe?
    @State private var showImport = false
    @AppStorage(SettingsKey.recipeFilter) private var filterRaw = ""

    var body: some View {
        NavigationStack {
            List {
                let custom = saved.compactMap(\.recipe)
                Section {
                    MethodFilterBar(recipes: custom + RecipeLibrary.presets, selection: methodBinding($filterRaw))
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                ForEach(RecipeFilter.sections(custom: custom, presets: RecipeLibrary.presets,
                                              method: BrewMethod(rawValue: filterRaw)), id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.recipes) { recipe in
                            NavigationLink { RecipeDetailView(recipe: recipe) } label: { RecipeRow(recipe: recipe) }
                        }
                    }
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { newRecipe = RecipeLibrary.blankRecipe() } label: {
                            Label("New recipe", systemImage: "square.and.pencil")
                        }
                        Button { showImport = true } label: {
                            Label("Import from file…", systemImage: "square.and.arrow.down")
                        }
                        let custom = saved.compactMap(\.recipe)
                        if !custom.isEmpty {
                            ShareLink(item: RecipeExport(recipes: custom),
                                      preview: SharePreview("My BrewLog recipes")) {
                                Label("Share my recipes", systemImage: "square.and.arrow.up")
                            }
                        }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add recipe")
                }
            }
            .sheet(item: $newRecipe) { recipe in
                NavigationStack { RecipeEditorView(recipe: recipe, isNew: true) }
            }
            .fileImport(isPresented: $showImport)
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(recipe.name).font(.headline)
                Spacer()
                Text(recipe.ratioText).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(recipe.author).font(.caption).foregroundStyle(.secondary)
            Text(recipe.tasteNotes).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 10) {
                Label(recipe.dose.grams, systemImage: "circle.grid.3x3.fill")
                Label(recipe.water.grams, systemImage: "drop.fill")
                Label("\(Int(recipe.temperature))°", systemImage: "thermometer.medium")
                Label(recipe.targetTime.mmss, systemImage: "timer")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Picker (from the Brew tab)

struct RecipePickerView: View {
    @Environment(BrewSetup.self) private var setup
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedRecipe.createdAt, order: .reverse) private var saved: [SavedRecipe]
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    @AppStorage(SettingsKey.recipeFilter) private var filterRaw = ""
    @State private var appeared = false

    /// The type of the brewer selected on the Brew tab.
    private var brewerMethod: BrewMethod? {
        equipment.first { $0.id == setup.brewerID && $0.type == .brewer }?.method
    }

    var body: some View {
        List {
            let custom = saved.compactMap(\.recipe)
            Section {
                MethodFilterBar(recipes: custom + RecipeLibrary.presets, selection: methodBinding($filterRaw),
                                brewerMethod: brewerMethod)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            ForEach(RecipeFilter.sections(custom: custom, presets: RecipeLibrary.presets,
                                          method: BrewMethod(rawValue: filterRaw)), id: \.title) { section in
                Section(section.title) { ForEach(section.recipes) { row($0) } }
            }
        }
        .navigationTitle("Choose recipe")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Start with the recipes for the brewer you've selected.
            guard !appeared else { return }
            appeared = true
            if let brewerMethod, brewerMethod != .universal { filterRaw = brewerMethod.rawValue }
        }
    }

    private func row(_ recipe: Recipe) -> some View {
        Button {
            setup.select(recipe)
            Haptics.tap()
            dismiss()
        } label: {
            HStack {
                RecipeRow(recipe: recipe)
                if setup.recipe.id == recipe.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// "All" plus one chip per brewer type. Tapping the selected chip again shows all recipes.
struct MethodFilterBar: View {
    let recipes: [Recipe]
    @Binding var selection: BrewMethod?
    var brewerMethod: BrewMethod? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { selection = nil } label: { Chip(title: "All", isSelected: selection == nil) }
                ForEach(RecipeFilter.methods(in: recipes)) { method in
                    Button {
                        selection = selection == method ? nil : method
                        Haptics.tap()
                    } label: {
                        Chip(title: method == brewerMethod ? "\(method.displayName) · yours" : method.displayName,
                             symbol: method.symbol, isSelected: selection == method)
                    }
                    .accessibilityIdentifier("recipes.filter.\(method.rawValue)")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}

/// The stored filter ("" = all) as a method.
func methodBinding(_ raw: Binding<String>) -> Binding<BrewMethod?> {
    Binding { BrewMethod(rawValue: raw.wrappedValue) } set: { raw.wrappedValue = $0?.rawValue ?? "" }
}

// MARK: - Detail

struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(BrewSetup.self) private var setup
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var saved: [SavedRecipe]
    @State private var editing: Recipe?
    @State private var confirmDelete = false

    private var isCustom: Bool { recipe.isCustom == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            MethodBadge(method: recipe.method)
                            Spacer()
                            Text(recipe.author).font(.caption).foregroundStyle(.secondary)
                        }
                        if !recipe.summary.isEmpty { Text(recipe.summary).font(.subheadline) }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "How it should taste")
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            if !recipe.tasteNotes.isEmpty { Text(recipe.tasteNotes).font(.subheadline) }
                            TasteProfileView(profile: recipe.taste)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Parameters")
                    Card {
                        VStack(spacing: 12) {
                            HStack {
                                StatView(value: recipe.dose.grams, label: "Coffee")
                                StatView(value: recipe.water.grams, label: "Water")
                                StatView(value: recipe.ratioText, label: "Ratio")
                            }
                            HStack {
                                StatView(value: "\(Int(recipe.temperature)) °C", label: "Temp")
                                StatView(value: recipe.targetTime.mmss, label: "Total time")
                                StatView(value: "\(Int(recipe.flowMin))–\(Int(recipe.flowMax))", label: "Pour g/s")
                            }
                            Divider()
                            Label(recipe.grind, systemImage: "dial.medium")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Steps")
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { _, step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(step.time.mmss)
                                        .font(.subheadline.weight(.bold))
                                        .monospacedDigit()
                                        .frame(width: 44, alignment: .leading)
                                    Image(systemName: step.kind.symbol).foregroundStyle(Color.accentColor).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.headline).font(.subheadline.weight(.semibold))
                                        if let note = step.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                    }
                }

                if !recipe.tips.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Tips")
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(recipe.tips, id: \.self) { tip in
                                    Label(tip, systemImage: "lightbulb").font(.subheadline)
                                }
                            }
                        }
                    }
                }

                Button {
                    setup.select(recipe)
                    router.tab = .brew
                } label: {
                    Label("Brew this", systemImage: "drop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 18))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(recipe.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if isCustom {
                        Button { editing = recipe } label: { Label("Edit", systemImage: "pencil") }
                    }
                    Button {
                        var copy = recipe
                        copy.id = "custom-\(UUID().uuidString)"
                        copy.name = isCustom ? "\(recipe.name) copy" : "My \(recipe.name)"
                        copy.isCustom = true
                        editing = copy
                    } label: { Label("Duplicate & edit", systemImage: "plus.square.on.square") }
                    ShareLink(item: RecipeExport(recipes: [recipe]), preview: SharePreview(recipe.name)) {
                        Label("Share as file", systemImage: "square.and.arrow.up")
                    }
                    if isCustom {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $editing) { draft in
            NavigationStack { RecipeEditorView(recipe: draft, isNew: draft.id != recipe.id) }
        }
        .confirmationDialog("Delete this recipe?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let item = saved.first(where: { $0.id == recipe.id }) { context.delete(item) }
                try? context.save()
                dismiss()
            }
        }
    }
}

// MARK: - Editor

private struct EditableStep: Identifiable {
    let id = UUID()
    var step: RecipeStep
}

struct RecipeEditorView: View {
    let isNew: Bool
    @State private var draft: Recipe
    @State private var steps: [EditableStep]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var saved: [SavedRecipe]

    init(recipe: Recipe, isNew: Bool) {
        self.isNew = isNew
        _draft = State(initialValue: recipe)
        _steps = State(initialValue: recipe.steps.map { EditableStep(step: $0) })
    }

    var body: some View {
        Form {
            Section("Recipe") {
                TextField("Name", text: $draft.name)
                TextField("Author", text: $draft.author)
                Picker("Method", selection: $draft.method) {
                    ForEach(BrewMethod.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section("Parameters") {
                numberRow("Coffee (g)", value: $draft.dose)
                numberRow("Water (g)", value: $draft.water)
                numberRow("Temperature (°C)", value: $draft.temperature)
                Stepper("Total time \(draft.targetTime.mmss)", value: $draft.targetTime, in: 30...1200, step: 5)
                numberRow("Min pour rate (g/s)", value: $draft.flowMin)
                numberRow("Max pour rate (g/s)", value: $draft.flowMax)
                TextField("Grind description", text: $draft.grind)
            }
            Section {
                ForEach($steps) { $item in
                    StepEditorRow(step: $item.step, showsValve: draft.method == .hybrid)
                }
                .onDelete { steps.remove(atOffsets: $0) }
                Button {
                    let lastTime = steps.last?.step.time ?? -30
                    let lastTarget = steps.last(where: { $0.step.kind.isPour })?.step.target ?? 0
                    steps.append(EditableStep(step: RecipeStep(kind: .pour, time: lastTime + 30,
                                                               target: min(lastTarget + 50, draft.water), note: nil)))
                } label: { Label("Add step", systemImage: "plus.circle.fill") }
                .disabled(steps.count >= InputLimits.maxSteps)
            } header: {
                Text("Steps")
            } footer: {
                Text("Pour targets are cumulative scale weights. BrewLog pings a little before each target and chimes when each step starts.")
            }
            Section("How it should taste") {
                TextField("Taste description", text: $draft.tasteNotes, axis: .vertical).lineLimit(2...5)
                Stepper("Acidity \(draft.taste.acidity)", value: $draft.taste.acidity, in: 1...5)
                Stepper("Sweetness \(draft.taste.sweetness)", value: $draft.taste.sweetness, in: 1...5)
                Stepper("Body \(draft.taste.body)", value: $draft.taste.body, in: 1...5)
                Stepper("Clarity \(draft.taste.clarity)", value: $draft.taste.clarity, in: 1...5)
            }
            Section("Description") {
                TextField("Summary", text: $draft.summary, axis: .vertical).lineLimit(2...6)
            }
        }
        .navigationTitle(isNew ? "New recipe" : "Edit recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }

    private func save() {
        var recipe = draft
        recipe.steps = steps.map(\.step)
        recipe.isCustom = true
        recipe = recipe.validated()
        if let existing = saved.first(where: { $0.id == recipe.id }) {
            existing.recipe = recipe
        } else {
            context.insert(SavedRecipe(recipe: recipe))
        }
        try? context.save()
        dismiss()
    }
}

private struct StepEditorRow: View {
    @Binding var step: RecipeStep
    let showsValve: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Action", selection: $step.kind) {
                    ForEach(StepKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden()
                Spacer()
                Stepper(step.time.mmss, value: $step.time, in: 0...1200, step: 5)
                    .monospacedDigit()
                    .fixedSize()
            }
            if step.kind.isPour {
                HStack {
                    Text("Pour to")
                    TextField("g", value: Binding(get: { step.target ?? 0 }, set: { step.target = $0 }),
                              format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                    Text("g total")
                    if showsValve {
                        Spacer()
                        Picker("Valve", selection: $step.valve) {
                            Text("–").tag(ValveState?.none)
                            Text("Open").tag(Optional(ValveState.open))
                            Text("Closed").tag(Optional(ValveState.closed))
                        }
                        .labelsHidden()
                    }
                }
                .font(.subheadline)
            }
            TextField("Note (optional)", text: Binding(get: { step.note ?? "" }, set: { step.note = $0.isEmpty ? nil : $0 }))
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}
