import SwiftUI
import SwiftData

/// First-launch setup assistant: brewer → filter → grinder → beans → scale. Every step is optional.
struct OnboardingView: View {
    /// Called when the assistant is finished or skipped.
    var onFinish: () -> Void
    /// Called when the user only wants to use the scale for now.
    var onJustWeigh: () -> Void

    enum Step: Int, CaseIterable {
        case welcome, brewer, filter, grinder, beans, scale, done
        static let questions: [Step] = [.brewer, .filter, .grinder, .beans, .scale]
    }

    @Environment(\.modelContext) private var context
    @Environment(BrewSetup.self) private var setup
    @Environment(ScaleManager.self) private var scale
    @Query private var equipment: [Equipment]

    @State private var step: Step = .welcome
    @State private var forward = true

    // Choices (preset names, in tap order: the first one becomes the default)
    @State private var brewers: [String] = []
    @State private var filters: [String] = []
    @State private var grinder: String?
    @State private var customGrinderName = ""
    @State private var customGrinderUnit: GrindUnit = .clicks
    @State private var grindValue: Double?
    @State private var grindText = ""
    @State private var beanName = ""
    @State private var roaster = ""
    @State private var roastLevel: RoastLevel = .light
    @State private var knowsRoastDate = false
    @State private var roastDate = Date()
    @FocusState private var focused: Bool

    private static let customGrinderKey = "__custom__"
    private let brewerPresets = EquipmentPreset.all.filter { $0.type == .brewer }
    private let filterPresets = EquipmentPreset.filters
    private let grinderPresets = EquipmentPreset.grinders

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step != .welcome { topBar }
                ZStack {
                    content
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if step != .welcome { bottomBar }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .animation(.spring(duration: 0.35), value: step)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
    }

    // MARK: Navigation

    private func go(to next: Step) {
        focused = false
        forward = next.rawValue > step.rawValue
        step = next
        Haptics.tap()
    }

    private func advance() {
        if step == .done {
            finish()
        } else if let next = Step(rawValue: step.rawValue + 1) {
            go(to: next)
        }
    }

    private var hasChoice: Bool {
        switch step {
        case .brewer: return !brewers.isEmpty
        case .filter: return !filters.isEmpty
        case .grinder:
            if grinder == Self.customGrinderKey { return !customGrinderName.sanitized(maxLength: 80).isEmpty }
            return grinder != nil
        case .beans: return !beanName.sanitized(maxLength: 80).isEmpty
        default: return true
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                if let previous = Step(rawValue: step.rawValue - 1) { go(to: previous) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.questions, id: \.self) { question in
                    Capsule()
                        .fill(question.rawValue <= step.rawValue ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(width: question == step ? 22 : 8, height: 8)
                }
            }
            .animation(.spring(duration: 0.3), value: step)
            Spacer()
            Button("Skip") { finish() }
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, alignment: .trailing)
                .accessibilityIdentifier("onboarding.skipAll")
                .opacity(step == .done ? 0 : 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Button(action: advance) {
                Text(primaryTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(hasChoice ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(hasChoice ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.next")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var primaryTitle: String {
        switch step {
        case .beans: return hasChoice ? "Continue" : "Add beans later"
        case .scale: return "Continue"
        case .done: return "Start brewing"
        default: return hasChoice ? "Continue" : "Skip this step"
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .brewer: brewerStep
        case .filter: filterStep
        case .grinder: grinderStep
        case .beans: beansStep
        case .scale: scaleStep
        case .done: doneStep
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            Image("Logo")
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Welcome to BrewLog").font(.largeTitle.bold())
                Text("Brew better pour-overs with live guidance from your scale and simple tips after every cup.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 18) {
                feature("drop.fill", "Guided pours", "Soft pings tell you when to stop and when the next pour starts.")
                feature("chart.xyaxis.line", "Every brew logged", "Pour curve, grind, beans and how it tasted.")
                feature("wand.and.stars", "Tips for your gear", "“Grind 2 clicks finer” instead of guesswork.")
            }
            .padding(.top, 6)
            Spacer(minLength: 10)
            VStack(spacing: 12) {
                Button { go(to: .brewer) } label: {
                    VStack(spacing: 2) {
                        Text("Set up my gear").font(.headline)
                        Text("About 1 minute").font(.caption).opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.start")

                Button {
                    UserDefaults.standard.set(true, forKey: SettingsKey.onboardingDone)
                    onJustWeigh()
                } label: {
                    Label("Skip, just use the scale", systemImage: "scalemass")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .accessibilityIdentifier("onboarding.justWeigh")

                Text("You can run the setup any time from the Gear tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Brewer

    private var brewerStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header("What do you brew with?", "Pick one or more. The first one becomes your default.")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(brewerPresets) { preset in
                        let index = brewers.firstIndex(of: preset.name)
                        SelectableTile(title: preset.name,
                                       subtitle: preset.method?.displayName ?? "",
                                       symbol: preset.method?.symbol ?? "cup.and.saucer",
                                       isSelected: index != nil,
                                       badge: index == 0 && brewers.count > 1 ? "Default" : nil) {
                            toggle(preset.name, in: &brewers)
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: Filter

    private var filterStep: some View {
        let shapes = Set(brewers.compactMap { name in brewerPresets.first { $0.name == name }?.shape })
        let matching = shapes.isEmpty ? filterPresets : filterPresets.filter { $0.shape.map(shapes.contains) ?? true }
        let others = shapes.isEmpty ? [] : filterPresets.filter { !matching.contains($0) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header("Which filter papers do you use?",
                       "Paper flow speed changes drawdown time, so BrewLog uses it in your tips.")
                if !shapes.isEmpty { SectionHeader(title: "Fits your brewer") }
                filterGrid(matching)
                if !others.isEmpty {
                    SectionHeader(title: "Other papers")
                    filterGrid(others)
                }
            }
            .padding()
        }
    }

    private func filterGrid(_ presets: [EquipmentPreset]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(presets) { preset in
                let index = filters.firstIndex(of: preset.name)
                SelectableTile(title: preset.name,
                               subtitle: filterSubtitle(preset),
                               symbol: flowSymbol(preset.flow),
                               isSelected: index != nil,
                               badge: index == 0 && filters.count > 1 ? "Default" : nil) {
                    toggle(preset.name, in: &filters)
                }
            }
        }
    }

    private func filterSubtitle(_ preset: EquipmentPreset) -> String {
        var parts: [String] = []
        if let flow = preset.flow { parts.append("\(flow.displayName) flow") }
        if let roast = preset.idealRoast { parts.append("\(roast.displayName.lowercased()) roasts") }
        return parts.joined(separator: " · ")
    }

    private func flowSymbol(_ flow: FilterFlow?) -> String {
        switch flow {
        case .fast: return "hare.fill"
        case .slow: return "tortoise.fill"
        default: return "gauge.with.dots.needle.50percent"
        }
    }

    // MARK: Grinder

    private var selectedGrinderSpec: GrinderSpec? {
        if grinder == Self.customGrinderKey { return Self.spec(for: customGrinderUnit) }
        return grinderPresets.first { $0.name == grinder }?.grinder
    }

    static func spec(for unit: GrindUnit) -> GrinderSpec {
        switch unit {
        case .clicks: return GrinderSpec(unit: .clicks, step: 1, adjustStep: 2)
        case .numbers: return GrinderSpec(unit: .numbers, step: 1, adjustStep: 1)
        case .dial: return GrinderSpec(unit: .dial, step: 0.1, adjustStep: 0.2)
        case .microns: return GrinderSpec(unit: .microns, step: 10, adjustStep: 50)
        }
    }

    private var grinderStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header("Which grinder do you use?",
                       "BrewLog learns your grinder's scale, so tips can say exactly how many clicks to change.")
                VStack(spacing: 0) {
                    ForEach(grinderPresets) { preset in
                        grinderRow(name: preset.name, detail: preset.grinder.map(grinderDetail) ?? "", key: preset.name)
                        Divider().padding(.leading, 52)
                    }
                    grinderRow(name: "Other grinder", detail: "Type its name and how its setting works", key: Self.customGrinderKey)
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if grinder == Self.customGrinderKey {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Grinder name", text: $customGrinderName)
                                .textFieldStyle(.roundedBorder)
                                .focused($focused)
                                .accessibilityIdentifier("onboarding.customGrinder")
                            Picker("Setting", selection: $customGrinderUnit) {
                                Text("Clicks").tag(GrindUnit.clicks)
                                Text("Numbers").tag(GrindUnit.numbers)
                                Text("Dial").tag(GrindUnit.dial)
                            }
                            .pickerStyle(.segmented)
                            Text("You can fine-tune step sizes later in Gear.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if let spec = selectedGrinderSpec {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your usual pour-over setting (optional)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    GrindInputView(spec: spec, value: $grindValue, text: $grindText, recommendation: nil,
                                   focus: $focused, fieldIdentifier: "onboarding.grind")
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal)
                .padding(.top, 6)
            }
        }
    }

    private func grinderDetail(_ spec: GrinderSpec) -> String {
        spec.rangeNote.isEmpty ? spec.unit.displayName : "\(spec.unit.displayName) · pour-over \(spec.rangeNote)"
    }

    private func grinderRow(name: String, detail: String, key: String) -> some View {
        Button {
            if grinder != key { grindValue = nil }
            grinder = grinder == key ? nil : key
            Haptics.tap()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: grinder == key ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(grinder == key ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("row.\(name)")
    }

    // MARK: Beans

    private var beansStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header("Got a bag of beans open?",
                       "Optional. Roast level and roast date help BrewLog explain sour or flat cups. You can also add beans after a brew.")
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Coffee name, e.g. Ethiopia Guji", text: $beanName)
                            .textFieldStyle(.roundedBorder)
                            .focused($focused)
                            .accessibilityIdentifier("onboarding.beanName")
                        TextField("Roaster (optional)", text: $roaster)
                            .textFieldStyle(.roundedBorder)
                            .focused($focused)
                        Text("Roast level").font(.subheadline.weight(.semibold))
                        FlowLayout(spacing: 8) {
                            ForEach(RoastLevel.allCases) { level in
                                Button {
                                    roastLevel = level
                                    Haptics.tap()
                                } label: {
                                    Chip(title: level.displayName, isSelected: roastLevel == level)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Toggle("I know the roast date", isOn: $knowsRoastDate)
                        if knowsRoastDate {
                            DatePicker("Roasted on", selection: $roastDate, in: ...Date(), displayedComponents: .date)
                        }
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Scale

    private var scaleStep: some View {
        @Bindable var scale = scale
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header("Connect your scale",
                       "BrewLog works with the BOOKOO Themis Mini. Switch it on and tap below. No scale? The timer works on its own.")
                ScaleStatusCard()
                Card {
                    Toggle(isOn: $scale.isDemo) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Demo scale").font(.body.weight(.medium))
                            Text("Simulated pours to try BrewLog without a scale").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Label("You can connect any time from the Brew tab.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    // MARK: Done

    private var doneStep: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(Color.green.gradient).frame(width: 96, height: 96)
                    Image(systemName: "checkmark").font(.system(size: 42, weight: .bold)).foregroundStyle(.white)
                }
                .padding(.top, 20)
                VStack(spacing: 6) {
                    Text("You're all set").font(.largeTitle.bold())
                    Text("Change anything later in the Gear and Beans tabs.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Card {
                    VStack(spacing: 14) {
                        summaryRow("Brewer", "cup.and.saucer.fill", brewers.first)
                        summaryRow("Filter", "doc.fill", filters.first)
                        summaryRow("Grinder", "gearshape.2.fill", grinderSummary)
                        summaryRow("Beans", "leaf.fill", beanName.sanitized(maxLength: 80).isEmpty ? nil : beanName)
                        summaryRow("Scale", "scalemass.fill", scale.isReady ? scale.displayName : "Timer only for now")
                    }
                }
            }
            .padding()
        }
    }

    private var grinderSummary: String? {
        guard let grinder else { return nil }
        let name = grinder == Self.customGrinderKey ? customGrinderName : grinder
        guard !name.isEmpty else { return nil }
        if let value = grindValue, let spec = selectedGrinderSpec { return "\(name) · \(spec.format(value))" }
        return name
    }

    private func summaryRow(_ title: String, _ symbol: String, _ value: String?) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "Skipped")
                .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.subheadline)
    }

    // MARK: Helpers

    private func toggle(_ name: String, in list: inout [String]) {
        if let index = list.firstIndex(of: name) {
            list.remove(at: index)
        } else {
            list.append(name)
        }
        Haptics.tap()
    }

    /// Saves the choices (reusing gear that already exists) and selects them for the next brew.
    private func finish() {
        var byName: [String: Equipment] = [:]
        for item in equipment where byName[item.name] == nil { byName[item.name] = item }

        func ensure(_ preset: EquipmentPreset) -> Equipment {
            if let existing = byName[preset.name] { return existing }
            let item = preset.makeEquipment()
            context.insert(item)
            byName[preset.name] = item
            return item
        }

        let chosenBrewers = brewers.compactMap { name in brewerPresets.first { $0.name == name } }.map(ensure)
        if let first = chosenBrewers.first { setup.brewerID = first.id }

        let chosenFilters = filters.compactMap { name in filterPresets.first { $0.name == name } }.map(ensure)
        if let first = chosenFilters.first { setup.filterID = first.id }

        var grinderItem: Equipment?
        if grinder == Self.customGrinderKey {
            let name = customGrinderName.sanitized(maxLength: InputLimits.maxNameLength)
            if !name.isEmpty {
                let item = byName[name] ?? Equipment(name: name, type: .grinder, grinder: Self.spec(for: customGrinderUnit))
                if byName[name] == nil { context.insert(item) }
                grinderItem = item
            }
        } else if let grinder, let preset = grinderPresets.first(where: { $0.name == grinder }) {
            grinderItem = ensure(preset)
        }
        if let grinderItem { setup.grinderID = grinderItem.id }

        let name = beanName.sanitized(maxLength: InputLimits.maxNameLength)
        if !name.isEmpty {
            let bean = Bean(name: name, roaster: roaster.sanitized(maxLength: InputLimits.maxNameLength))
            bean.roastLevel = roastLevel
            bean.roastDate = knowsRoastDate ? min(roastDate, Date()) : nil
            context.insert(bean)
            setup.beanID = bean.id
        }

        // Pin after bean + grinder are set, so the typed setting isn't replaced by a history recommendation.
        if grinderItem != nil, let grindValue, grindValue.isFinite {
            setup.pinGrind(grindValue.clamped(0, 10_000))
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: SettingsKey.onboardingDone)
        onFinish()
    }
}

/// Large tappable card used in the setup assistant.
struct SelectableTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isSelected: Bool
    var badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                HStack(spacing: 6) {
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tile.\(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
