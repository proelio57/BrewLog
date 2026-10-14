import SwiftUI
import SwiftData

struct BrewConfig: Identifiable {
    let id = UUID()
    let recipe: Recipe
    let dose: Double
    let waterTemp: Double
    let bean: Bean?
    let brewer: Equipment?
    let grinder: Equipment?
    let filter: Equipment?
    let grindValue: Double?
    let grindText: String
}

struct BrewSetupView: View {
    @Environment(BrewSetup.self) private var setup
    @Environment(ScaleManager.self) private var scale
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.setupBannerDismissed) private var setupBannerDismissed = false
    @Query(filter: #Predicate<Bean> { !$0.isArchived }, sort: \Bean.createdAt, order: .reverse) private var beans: [Bean]
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    @Query(sort: \Brew.date, order: .reverse) private var brews: [Brew]

    @State private var activeBrew: BrewConfig?
    @State private var showNewBean = false
    @State private var showSettings = false
    @State private var showPresets = false
    @FocusState private var grindFocused: Bool

    private var brewers: [Equipment] { equipment.filter { $0.type == .brewer } }
    private var grinders: [Equipment] { equipment.filter { $0.type == .grinder } }
    private var filters: [Equipment] { equipment.filter { $0.type == .filter } }
    private var selectedGrinder: Equipment? { grinders.first { $0.id == setup.grinderID } }
    private var selectedBean: Bean? { beans.first { $0.id == setup.beanID } }

    private var recommendation: GrindRecommendation? {
        GrindRecommender.recommend(beanID: setup.beanID, grinder: selectedGrinder, recipeID: setup.recipe.id, brews: brews)
    }

    // Split into parts: as one expression the body is too complex for the type checker.
    var body: some View {
        NavigationStack {
            observingSetup(presentingSheets(screen))
        }
    }

    private var screen: some View {
        ScrollView {
            VStack(spacing: 18) {
                if equipment.isEmpty && !setupBannerDismissed { setupBanner }
                ScaleStatusCard()
                recipeCard
                doseCard
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Coffee")
                    beanCard
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Gear & grind")
                    gearCard
                }
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Brew")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { router.present(.quickWeigh) } label: {
                    Label("Weigh", systemImage: "scalemass")
                }
                .accessibilityIdentifier("brew.quickWeigh")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { grindFocused = false }
            }
        }
        .safeAreaInset(edge: .bottom) { startButton }
    }

    private func presentingSheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: $showNewBean) {
                NavigationStack {
                    BeanEditorView(bean: nil) { bean in setup.beanID = bean.id }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView(showsDone: true) }
            }
            .sheet(isPresented: $showPresets) {
                NavigationStack { PresetPickerView() }
            }
            .fullScreenCover(item: $activeBrew) { config in
                BrewSessionView(config: config)
            }
    }

    private func observingSetup(_ content: some View) -> some View {
        content
            .onChange(of: grinders.map(\.id)) { old, new in reconcile(&setup.grinderID, ids: new, previous: old) }
            .onChange(of: brewers.map(\.id)) { old, new in reconcile(&setup.brewerID, ids: new, previous: old) }
            .onChange(of: filters.map(\.id)) { old, new in reconcile(&setup.filterID, ids: new, previous: old) }
            .onChange(of: setup.beanID) { applyRecommendation() }
            .onChange(of: setup.grinderID) { applyRecommendation() }
            .onChange(of: setup.recipe.id) { applyRecommendation() }
            .onAppear {
                if setup.grindValue == nil { applyRecommendation() }
            }
    }

    // MARK: Cards

    private var setupBanner: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set up your gear").font(.headline)
                    Text("Add your brewer, filter and grinder in about a minute so tips can be precise.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Start setup") { router.present(.onboarding) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("brew.startSetup")
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation { setupBannerDismissed = true }
                } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
    }

    private var recipeCard: some View {
        NavigationLink {
            RecipePickerView()
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(setup.recipe.name).font(.title2.bold()).foregroundStyle(.primary)
                            Text(setup.recipe.author).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        MethodBadge(method: setup.recipe.method)
                    }
                    Text(setup.recipe.tasteNotes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    TasteProfileView(profile: setup.recipe.taste)
                    HStack {
                        Text("Change recipe").font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var doseCard: some View {
        @Bindable var setup = setup
        let recipe = setup.scaledRecipe
        return Card {
            VStack(spacing: 14) {
                HStack {
                    StatView(value: setup.dose.grams1, label: "Coffee", symbol: "circle.grid.3x3.fill")
                    StatView(value: recipe.water.grams, label: "Water", symbol: "drop.fill")
                    StatView(value: recipe.ratioText, label: "Ratio")
                    StatView(value: "\(Int(setup.waterTemp))°", label: "Temp", symbol: "thermometer.medium")
                }
                Divider()
                Stepper(value: $setup.dose, in: 5...60, step: 0.5) {
                    Label("Coffee dose", systemImage: "scalemass")
                }
                Stepper(value: $setup.waterTemp, in: 70...100, step: 1) {
                    Label("Water temperature", systemImage: "thermometer.medium")
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

    private var beanCard: some View {
        @Bindable var setup = setup
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    MenuPickerRow(title: "Beans", symbol: "leaf.fill",
                                  options: beans.map { PickerOption(id: $0.id, name: $0.displayName) },
                                  selection: $setup.beanID, noneLabel: "None")
                    Button { showNewBean = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .accessibilityLabel("Add beans")
                }
                if let bean = selectedBean {
                    HStack(spacing: 12) {
                        Label(bean.roastLevel.displayName, systemImage: "flame")
                        if let days = bean.daysOffRoast { Label("\(days) d off roast", systemImage: "calendar") }
                        Label(bean.remaining.grams + " left", systemImage: "bag")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Optional. You can also add the beans after brewing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var gearCard: some View {
        @Bindable var setup = setup
        return Card {
            VStack(spacing: 14) {
                gearRow("Brewer", symbol: "cup.and.saucer.fill", items: brewers, selection: $setup.brewerID)
                Divider()
                VStack(spacing: 4) {
                    gearRow("Filter", symbol: "doc.fill", items: filters, selection: $setup.filterID)
                    if let filter = filters.first(where: { $0.id == setup.filterID }), !filter.subtitle.isEmpty {
                        Text(filter.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                Divider()
                gearRow("Grinder", symbol: "gearshape.2.fill", items: grinders, selection: $setup.grinderID)
                GrindInputView(spec: selectedGrinder?.grinderSpec, value: $setup.grindValue, text: $setup.grindText,
                               recommendation: recommendation, focus: $grindFocused)
            }
        }
    }

    @ViewBuilder
    private func gearRow(_ title: String, symbol: String, items: [Equipment], selection: Binding<UUID?>) -> some View {
        if items.isEmpty {
            HStack {
                Label(title, systemImage: symbol).foregroundStyle(.secondary)
                Spacer()
                Button("Add \(title.lowercased())") { showPresets = true }
            }
            .font(.subheadline)
        } else {
            MenuPickerRow(title: title, symbol: symbol,
                          options: items.map { PickerOption(id: $0.id, name: $0.name) },
                          selection: selection)
        }
    }

    /// Clears selections of deleted gear and auto-selects newly added gear when nothing is selected.
    private func reconcile(_ selection: inout UUID?, ids: [UUID], previous: [UUID]) {
        if let current = selection, !ids.contains(current) { selection = nil }
        if selection == nil, let added = ids.first(where: { !previous.contains($0) }) { selection = added }
    }

    private var startButton: some View {
        Button {
            startBrew()
        } label: {
            HStack {
                Image(systemName: scale.isReady ? "scalemass.fill" : "timer")
                Text(scale.isReady ? "Start brew" : "Start brew (timer only)")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(.white)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.bar.opacity(0.0))
    }

    // MARK: Actions

    private func applyRecommendation() {
        // Keep a grind the user set explicitly (setup assistant, "Brew again") for this bean + grinder.
        guard !setup.isGrindPinned else { return }
        if let recommendation { setup.grindValue = recommendation.value }
    }

    private func startBrew() {
        grindFocused = false
        activeBrew = BrewConfig(
            recipe: setup.scaledRecipe,
            dose: setup.dose,
            waterTemp: setup.waterTemp,
            bean: selectedBean,
            brewer: brewers.first { $0.id == setup.brewerID },
            grinder: selectedGrinder,
            filter: filters.first { $0.id == setup.filterID },
            grindValue: selectedGrinder == nil ? nil : setup.grindValue,
            grindText: setup.grindText
        )
    }
}

/// Grind entry on the grinder's own scale, with finer/coarser buttons and a history-based suggestion.
struct GrindInputView: View {
    /// The grinder's scale, or nil for free-text grind entry.
    let spec: GrinderSpec?
    @Binding var value: Double?
    @Binding var text: String
    let recommendation: GrindRecommendation?
    var focus: FocusState<Bool>.Binding
    var fieldIdentifier = "grind.value"

    var body: some View {
        if let spec {
            VStack(spacing: 10) {
                HStack {
                    stepButton(title: "Finer", symbol: "minus", coarser: false, spec: spec)
                    Spacer()
                    VStack(spacing: 0) {
                        TextField("–", value: $value, format: .number.precision(.fractionLength(0...2)))
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                            .keyboardType(.decimalPad)
                            .focused(focus)
                            .frame(maxWidth: 140)
                            .accessibilityIdentifier(fieldIdentifier)
                        Text(spec.unit.suffix.isEmpty ? spec.unit.displayName.lowercased() : spec.unit.suffix)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    stepButton(title: "Coarser", symbol: "plus", coarser: true, spec: spec)
                }
                if let recommendation, recommendation.value != value {
                    Button {
                        value = recommendation.value
                        Haptics.tap()
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: "wand.and.stars")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use \(spec.format(recommendation.value))").font(.subheadline.weight(.semibold))
                                Text(recommendation.reason).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                } else if let recommendation {
                    Label(recommendation.reason, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !spec.rangeNote.isEmpty {
                    Text("Typical pour-over range: \(spec.rangeNote)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Grind setting (e.g. medium-fine)", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused(focus)
                Text("Add your grinder in Gear to track exact settings and get click-by-click suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepButton(title: String, symbol: String, coarser: Bool, spec: GrinderSpec) -> some View {
        Button {
            let base = value ?? recommendation?.value ?? 0
            let delta = (coarser == spec.finerIsLower) ? spec.step : -spec.step
            value = max(0, ((base + delta) / spec.step).rounded() * spec.step)
            Haptics.tap()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemFill), in: Circle())
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
