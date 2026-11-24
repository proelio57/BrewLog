import SwiftUI
import SwiftData

struct GearListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    @State private var showPresets = false
    @State private var showCustom = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { router.present(.onboarding) } label: {
                        Label("Setup assistant", systemImage: "wand.and.stars")
                    }
                    .accessibilityIdentifier("gear.setupAssistant")
                    NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
                }
                ToolsSection()
                ForEach(GearGroup.all) { group in
                    let items = equipment.filter(group.contains)
                    if !items.isEmpty {
                        Section(group.title) {
                            ForEach(items) { item in
                                NavigationLink { EquipmentEditorView(item: item) } label: { EquipmentRow(item: item) }
                            }
                            .onDelete { offsets in
                                for index in offsets { context.delete(items[index]) }
                                try? context.save()
                            }
                        }
                    }
                }
                Section {
                    Button { showPresets = true } label: { Label("Add from presets", systemImage: "square.grid.2x2") }
                    Button { showCustom = true } label: { Label("Add custom gear", systemImage: "plus") }
                } footer: {
                    Text("Your grinder's scale (clicks, numbers, dial) lets BrewLog suggest exact grind changes. Filter flow speed and roast suitability are used in the analysis.")
                }
            }
            .navigationTitle("Gear")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showPresets = true } label: { Label("From presets", systemImage: "square.grid.2x2") }
                        Button { showCustom = true } label: { Label("Custom", systemImage: "pencil") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showPresets) { NavigationStack { PresetPickerView() } }
            .sheet(isPresented: $showCustom) { NavigationStack { EquipmentEditorView(item: nil) } }
        }
    }
}

/// The gear list's sections: the equipment types, with espresso machines apart from the pour-over brewers.
struct GearGroup: Identifiable {
    let id: String
    let title: String
    let contains: (Equipment) -> Bool

    static let all: [GearGroup] = EquipmentType.allCases.flatMap { type -> [GearGroup] in
        guard type == .brewer else {
            return [GearGroup(id: type.rawValue, title: type.displayName) { $0.type == type }]
        }
        return [GearGroup(id: "brewer", title: type.displayName) { $0.type == .brewer && !$0.isEspressoMachine },
                GearGroup(id: "espresso", title: "Espresso machines") { $0.isEspressoMachine }]
    }
}

private struct EquipmentRow: View {
    let item: Equipment
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isEspressoMachine ? "cup.and.heat.waves.fill" : item.type.symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PresetPickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var equipment: [Equipment]
    @State private var search = ""

    private let order: [EquipmentType] = [.brewer, .filter, .grinder, .kettle, .scale, .water]

    /// Like the gear list: espresso machines in their own section.
    private var sections: [(title: String, contains: (EquipmentPreset) -> Bool)] {
        order.flatMap { type -> [(title: String, contains: (EquipmentPreset) -> Bool)] in
            guard type == .brewer else { return [(type.displayName, { $0.type == type })] }
            return [(type.displayName, { $0.type == .brewer && $0.method != .espresso }),
                    ("Espresso machines", { $0.type == .brewer && $0.method == .espresso })]
        }
    }

    var body: some View {
        List {
            ForEach(sections, id: \.title) { section in
                let presets = EquipmentPreset.all.filter {
                    section.contains($0) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
                }
                if !presets.isEmpty {
                    Section(section.title) {
                        ForEach(presets) { preset in
                            let added = equipment.contains { $0.name == preset.name }
                            Button {
                                guard !added else { return }
                                context.insert(preset.makeEquipment())
                                try? context.save()
                                Haptics.tap()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.name).foregroundStyle(.primary)
                                        if !preset.notes.isEmpty {
                                            Text(preset.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        } else if let grinder = preset.grinder {
                                            Text("Steps of \(grinder.formatDelta(grinder.adjustStep))\(grinder.rangeNote.isEmpty ? "" : " · \(grinder.rangeNote)")")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                        .foregroundStyle(added ? Color.green : Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Add gear")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}

/// Create or edit equipment, including grinder scales and filter properties.
struct EquipmentEditorView: View {
    let item: Equipment?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: EquipmentType = .grinder
    @State private var method: BrewMethod = .v60
    @State private var flow: FilterFlow = .medium
    @State private var idealRoast: RoastLevel?
    @State private var spec = GrinderSpec()
    @State private var notes = ""
    @State private var waterHardness: Double?
    @State private var waterAlkalinity: Double?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                if item == nil {
                    Picker("Type", selection: $type) {
                        ForEach(EquipmentType.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) }
                    }
                }
            }

            switch type {
            case .brewer:
                if item?.isEspressoMachine == true {
                    // An espresso machine has no pour-over method to pick; what matters is how BrewLog reaches it.
                    EspressoMachineConnectionSection(machineName: name)
                } else {
                    Section("Brewer") {
                        Picker("Method", selection: $method) {
                            ForEach(BrewMethod.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                }
            case .filter:
                Section {
                    Picker("Flow speed", selection: $flow) {
                        ForEach(FilterFlow.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Designed for", selection: $idealRoast) {
                        Text("Any roast").tag(RoastLevel?.none)
                        ForEach(RoastLevel.allCases) { Text($0.displayName).tag(Optional($0)) }
                    }
                } header: {
                    Text("Filter paper")
                } footer: {
                    Text("Faster papers shorten drawdown (less extraction). Slower papers lengthen it. Used in the brew analysis.")
                }
            case .grinder:
                Section {
                    Picker("Setting unit", selection: $spec.unit) {
                        ForEach(GrindUnit.allCases) { Text($0.displayName).tag($0) }
                    }
                    decimalRow("Smallest step", value: $spec.step)
                    decimalRow("Typical adjustment", value: $spec.adjustStep)
                    Toggle("Lower number = finer", isOn: $spec.finerIsLower)
                    TextField("Pour-over range (e.g. 20–30 clicks)", text: $spec.rangeNote)
                } header: {
                    Text("Grind scale")
                } footer: {
                    Text("Example: with a typical adjustment of 2, BrewLog suggests going from 24 to 22 clicks when your brew tastes sour and ran fast.")
                }
                Section {
                    optionalRow("Filter starting point", value: $spec.defaultGrind)
                    optionalRow("µm per step", value: $spec.micronsPerStep)
                } header: {
                    Text("Calibration")
                } footer: {
                    Text("Your setting for a medium-fine pour-over and how far one smallest step moves the burrs (from the manufacturer). With both, BrewLog translates recipe grind sizes and other grinders' settings to this grinder.")
                }
            case .water:
                Section {
                    optionalRow("Hardness (GH, ppm)", value: $waterHardness)
                    optionalRow("Alkalinity (KH, ppm)", value: $waterAlkalinity)
                    NavigationLink { WaterCalculatorView() } label: { Label("Water recipes", systemImage: "drop.triangle") }
                } header: {
                    Text("Minerals")
                } footer: {
                    Text("In mg/L as CaCO3, from your recipe or the water report. Optional.")
                }
            default:
                EmptyView()
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
            }
        }
        .navigationTitle(item == nil ? "New gear" : "Edit gear")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(name.sanitized(maxLength: InputLimits.maxNameLength).isEmpty)
            }
        }
        .onAppear(perform: load)
    }

    private func decimalRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func optionalRow(_ title: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("–", value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let item else { return }
        waterHardness = item.waterHardness
        waterAlkalinity = item.waterAlkalinity
        name = item.name
        type = item.type
        method = item.method ?? .v60
        flow = item.filterFlow ?? .medium
        idealRoast = item.idealRoast
        spec = GrindConverter.calibrated(item.grinderSpec, name: item.name)
        notes = item.notes
    }

    private func save() {
        let target = item ?? Equipment(name: "", type: type)
        target.name = name.sanitized(maxLength: InputLimits.maxNameLength)
        target.type = type
        target.notes = notes.sanitized(maxLength: InputLimits.maxLongText)
        switch type {
        case .brewer:
            target.method = method
        case .filter:
            target.filterFlow = flow
            target.idealRoast = idealRoast
        case .grinder:
            var clean = spec
            clean.step = spec.step.clamped(0.01, 100)
            clean.adjustStep = max(spec.adjustStep.clamped(0.01, 100), clean.step)
            clean.rangeNote = spec.rangeNote.sanitized(maxLength: InputLimits.maxShortText)
            clean.defaultGrind = spec.defaultGrind.map { $0.clamped(0, 10_000) }
            clean.micronsPerStep = spec.micronsPerStep.flatMap { $0 > 0 ? $0.clamped(0.1, 1_000) : nil }
            target.grinderSpec = clean
        case .water:
            target.waterHardness = waterHardness.map { $0.clamped(0, WaterChemistry.Limits.maxPPM) }
            target.waterAlkalinity = waterAlkalinity.map { $0.clamped(0, WaterChemistry.Limits.maxPPM) }
        default:
            break
        }
        if item == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}

// MARK: - Settings

/// Settings: imports the profiles saved on the GaggiMate as espresso recipes.
struct MachineProfileImportRow: View {
    @Environment(MachineManager.self) private var machine
    @Environment(\.modelContext) private var context
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        Button(action: importProfiles) {
            HStack {
                Label("Import profiles as recipes", systemImage: "square.and.arrow.down.on.square")
                Spacer()
                if loading { ProgressView() }
            }
        }
        .disabled(!machine.isConnected || loading)
        .accessibilityIdentifier("machine.importProfiles")
        if let message {
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func importProfiles() {
        loading = true
        message = nil
        machine.fetchProfiles { recipes in
            loading = false
            guard let recipes else {
                message = "The machine didn't send its profiles. Check the connection and try again."
                return
            }
            guard !recipes.isEmpty else {
                message = "No brew profiles on the machine besides the ones BrewLog sent."
                return
            }
            do {
                let summary = try DataImporter.importRecipes(recipes, into: context)
                message = summary.message + " They're with the espresso recipes."
            } catch {
                message = "Import failed: \(error.localizedDescription)"
            }
        }
    }
}

/// Gear editor of an espresso machine: how BrewLog connects to it (the same setting as Settings → Espresso machine).
private struct EspressoMachineConnectionSection: View {
    let machineName: String
    @Environment(MachineManager.self) private var machine

    var body: some View {
        @Bindable var machine = machine
        let suggested = MachineKind.suggested(forBrewerNamed: machineName)
        Section {
            Picker("Connection", selection: $machine.kind) {
                ForEach(MachineKind.allCases) { kind in
                    Text(kind == .none ? "Not connected" : kind.displayName).tag(kind)
                }
            }
            if let suggested, machine.kind != suggested {
                Button("Connect as \(suggested.displayName)") { machine.kind = suggested }
            }
            switch machine.kind {
            case .decent: DecentMachineRow()
            case .laMarzocco: LaMarzoccoAccountRow()
            default: EmptyView()
            }
            if machine.kind != .none {
                LabeledContent("Status", value: statusText)
            }
            NavigationLink("Machine settings") { SettingsMachineView() }
        } header: {
            Text("Espresso machine")
        } footer: {
            Text("BrewLog connects one machine at a time. GaggiMate's address, the DE1 pairing and the La Marzocco account are under Machine settings.")
        }
    }

    private var statusText: String {
        switch machine.state {
        case .off: return "Off"
        case .connecting: return "Connecting…"
        case .connected:
            if let temperature = machine.status.temperature { return String(format: "Connected · %.1f °C", temperature) }
            return "Connected"
        case .unreachable: return "Not reachable"
        }
    }
}
