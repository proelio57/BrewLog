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
                ForEach(EquipmentType.allCases) { type in
                    let items = equipment.filter { $0.type == type }
                    if !items.isEmpty {
                        Section(type.displayName) {
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

private struct EquipmentRow: View {
    let item: Equipment
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.type.symbol)
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

    var body: some View {
        List {
            ForEach(order) { type in
                let presets = EquipmentPreset.all.filter {
                    $0.type == type && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
                }
                if !presets.isEmpty {
                    Section(type.displayName) {
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
                Section("Brewer") {
                    Picker("Method", selection: $method) {
                        ForEach(BrewMethod.allCases) { Text($0.displayName).tag($0) }
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

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let item else { return }
        name = item.name
        type = item.type
        method = item.method ?? .v60
        flow = item.filterFlow ?? .medium
        idealRoast = item.idealRoast
        spec = item.grinderSpec
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
            target.grinderSpec = clean
        default:
            break
        }
        if item == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}

// MARK: - Settings

struct SettingsView: View {
    var showsDone = false
    @Environment(\.dismiss) private var dismiss
    @Environment(ScaleManager.self) private var scale
    @Environment(MachineManager.self) private var machine
    @State private var machineHost = MachineManager.shared.host

    @AppStorage(SettingsKey.autoStartThreshold) private var autoStartThreshold = 1.5
    @AppStorage(SettingsKey.pingLeadMode) private var pingLeadMode = PingLeadMode.auto.rawValue
    @AppStorage(SettingsKey.pingLeadGrams) private var pingLeadGrams = 3.0
    @AppStorage(SettingsKey.reactionTime) private var reactionTime = 0.6
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = true
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKey.soundVolume) private var soundVolume = 0.8
    @AppStorage(SettingsKey.silentModeSound) private var silentModeSound = true
    @AppStorage(SettingsKey.countdownTicks) private var countdownTicks = false
    @AppStorage(SettingsKey.finishPing) private var finishPing = true
    @AppStorage(SettingsKey.keepAwake) private var keepAwake = true
    @AppStorage(SettingsKey.onlineRecipes) private var onlineRecipes = true
    @State private var showScale = false
    private let feed = RecipeFeed.shared

    var body: some View {
        @Bindable var scale = scale
        Form {
            Section("Scale") {
                Button { showScale = true } label: {
                    LabeledContent("BOOKOO scale", value: scale.isDemo ? "Demo" : scale.state.label)
                }
                Toggle("Demo scale (simulated pours)", isOn: $scale.isDemo)
            }

            machineSection

            Section {
                VStack(alignment: .leading) {
                    Text("Auto-start at \(autoStartThreshold, specifier: "%.1f") g")
                    Slider(value: $autoStartThreshold, in: 0.5...5, step: 0.5)
                }
                Picker("Ping buffer", selection: $pingLeadMode) {
                    ForEach(PingLeadMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if pingLeadMode == PingLeadMode.fixed.rawValue {
                    Stepper("Ping \(Int(pingLeadGrams)) g before target", value: $pingLeadGrams, in: 0...15)
                } else {
                    VStack(alignment: .leading) {
                        Text("Reaction time \(reactionTime, specifier: "%.1f") s")
                        Slider(value: $reactionTime, in: 0.2...1.5, step: 0.1)
                    }
                }
                Toggle("3-2-1 ticks before each step", isOn: $countdownTicks)
                Toggle("Chime at target brew time", isOn: $finishPing)
                Toggle("Keep screen on while brewing", isOn: $keepAwake)
            } header: {
                Text("Brew assistant")
            } footer: {
                Text("Automatic buffer = your pour rate × reaction time + 1 g, so you hear the ping early enough to stop right on target. Increase the reaction time if you often overpour.")
            }

            Section("Sound & haptics") {
                Toggle("Sounds", isOn: $soundEnabled)
                if soundEnabled {
                    VStack(alignment: .leading) {
                        Text("Volume")
                        Slider(value: $soundVolume, in: 0.1...1)
                    }
                    Toggle("Play in silent mode", isOn: $silentModeSound)
                        .onChange(of: silentModeSound) { SoundPlayer.shared.prepare() }
                }
                Toggle("Haptics", isOn: $hapticsEnabled)
                HStack {
                    testButton("Target", .target)
                    testButton("Next step", .nextStep)
                    testButton("Finish", .finish)
                }
            }

            if RecipeFeed.feedURL != nil {
                Section {
                    Toggle("Online recipe updates", isOn: $onlineRecipes)
                    if onlineRecipes {
                        LabeledContent("Last checked",
                                       value: feed.lastSync?.formatted(.relative(presentation: .named)) ?? "Never")
                        Button {
                            Task { await feed.syncIfNeeded(force: true) }
                        } label: {
                            HStack {
                                Text("Check now")
                                if feed.isSyncing { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(feed.isSyncing)
                        if let error = feed.lastError {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Recipes")
                } footer: {
                    Text("BrewLog checks for new and updated recipes every few hours. Your own recipes are never changed.")
                }
            }

            BackupSection()

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            } header: {
                Text("About")
            } footer: {
                Text(RecipeFeed.feedURL == nil
                     ? "BrewLog has no account, no analytics and no network access. Everything stays on this device."
                     : "BrewLog has no account and no analytics. The only network access is downloading the recipe list. Everything else stays on this device.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        // The sound test buttons start the audio engine, which would keep the app awake in the background.
        .onDisappear { SoundPlayer.shared.stop() }
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(isPresented: $showScale) { ScaleConnectSheet() }
    }

    @ViewBuilder
    private var machineSection: some View {
        @Bindable var machine = machine
        Section {
            Picker("Machine", selection: $machine.kind) {
                ForEach(MachineKind.allCases) { Text($0.displayName).tag($0) }
            }
            if machine.kind == .gaggimate {
                HStack {
                    Text("Address")
                    TextField("gaggimate.local", text: $machineHost)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { if gaggiMateURL(host: machineHost) != nil { machine.host = machineHost } }
                }
                if gaggiMateURL(host: machineHost) == nil {
                    Text("Enter a host name like gaggimate.local or an IP address like 192.168.1.20.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if machine.kind != .none {
                LabeledContent("Status", value: machineStateText)
            }
            PressureMonitorRow()
        } header: {
            Text("Espresso machine")
        } footer: {
            Text("Pressure sensor: BOOKOO Espresso Monitor over Bluetooth, works with any machine. GaggiMate: BrewLog connects over your Wi-Fi, records pressure, temperature and flow, follows the shot and can start it, switch modes and send recipes as profiles. Use the address from GaggiMate's web interface. Your scale can stay connected to GaggiMate; BrewLog then reads the weight from there.")
        }
        .onDisappear { if machine.host != machineHost, gaggiMateURL(host: machineHost) != nil { machine.host = machineHost } }
    }

    private var machineStateText: String {
        switch machine.state {
        case .off: return "Off"
        case .connecting: return "Connecting…"
        case .connected:
            if let temperature = machine.status.temperature { return String(format: "Connected · %.1f °C", temperature) }
            return "Connected"
        case .unreachable: return "Not reachable"
        }
    }

    private func testButton(_ title: String, _ cue: BrewCue) -> some View {
        Button(title) {
            SoundPlayer.shared.prepare()
            SoundPlayer.shared.cue(cue)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }
}
