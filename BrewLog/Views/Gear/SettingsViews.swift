import SwiftUI
import SwiftData

extension MachineManager {
    /// "Off", "Connecting…", "Connected · 93.3 °C", "Not reachable".
    var stateText: String {
        switch state {
        case .off: return "Off"
        case .connecting: return "Connecting…"
        case .connected:
            if let temperature = status.temperature { return String(format: "Connected · %.1f °C", temperature) }
            return "Connected"
        case .unreachable: return "Not reachable"
        }
    }
}

/// Settings: a short list of topics, each with a one-line summary; every topic opens its own page.
struct SettingsView: View {
    var showsDone = false
    @Environment(\.dismiss) private var dismiss
    @Environment(ScaleManager.self) private var scale
    @Environment(MachineManager.self) private var machine
    @AppStorage(SettingsKey.autoStopShot) private var autoStopShot = true
    @AppStorage(SettingsKey.pressureFocus) private var pressureFocus = PressureFocusMode.automatic
    @AppStorage(SettingsKey.powerPlug) private var powerPlug = PlugKind.none
    @AppStorage(SettingsKey.powerAutoOff) private var powerAutoOff = 0.0
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = true
    @AppStorage(SettingsKey.voicePrompts) private var voicePrompts = false

    var body: some View {
        List {
            Section {
                SettingsLink(title: "Scale", symbol: "scalemass",
                             summary: "\(scale.model.defaultName) · \(scale.isDemo ? "Demo" : scale.state.label)") {
                    SettingsScaleView()
                }
            }
            Section("Espresso") {
                SettingsLink(title: "Machine", symbol: "cup.and.saucer",
                             summary: machine.kind == .none ? "Not connected" : "\(machine.kind.displayName) · \(machine.stateText)") {
                    SettingsMachineView()
                }
                SettingsLink(title: "Shot", symbol: "timer",
                             summary: (autoStopShot ? "Stops at the yield" : "No auto-stop") + " · Pressure view: \(pressureFocus.title)") {
                    SettingsShotView()
                }
                SettingsLink(title: "Power & smart plug", symbol: "powerplug", summary: powerSummary) {
                    SettingsPowerView()
                }
            }
            Section("Brewing") {
                SettingsLink(title: "Brew assistant", symbol: "bell", summary: "Pings, ticks, rinsing, weighing the beans") {
                    SettingsBrewView()
                }
                SettingsLink(title: "Sound, haptics & voice", symbol: "speaker.wave.2",
                             summary: (soundEnabled ? "Sounds on" : "Sounds off") + " · Voice " + (voicePrompts ? "on" : "off")) {
                    SettingsSoundView()
                }
            }
            Section {
                SettingsLink(title: "Recipes, backup & data", symbol: "externaldrive",
                             summary: Features.askAI ? "Online recipes, backup, Claude" : "Online recipes, backup") {
                    SettingsDataView()
                }
            }
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            } header: {
                Text("About")
            } footer: {
                Text((RecipeFeed.feedURL == nil
                      ? "BrewLog has no account, no analytics and no network access of its own. Everything stays on this device"
                      : "BrewLog has no account and no analytics. Its own network access is downloading the recipe list. Everything else stays on this device")
                     + (Features.askAI ? ", unless you turn on Git backup or ask Claude about a bean."
                                       : ", unless you turn on Git backup."))
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var powerSummary: String {
        guard [.gaggimate, .demo].contains(machine.kind) else { return "For GaggiMate" }
        let plug = powerPlug == .none ? "No smart plug" : "Plug: \(powerPlug.title)"
        return powerAutoOff > 0 ? "\(plug) · Auto-off \(Int(powerAutoOff / 60)) min" : plug
    }
}

/// One row of the Settings list: icon, title, one line of what is set.
private struct SettingsLink<Destination: View>: View {
    let title: String
    let symbol: String
    var summary: String?
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let summary {
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Scale

struct SettingsScaleView: View {
    @Environment(ScaleManager.self) private var scale
    @State private var showScale = false

    var body: some View {
        @Bindable var scale = scale
        Form {
            Section {
                Button { showScale = true } label: {
                    LabeledContent(scale.model.defaultName, value: scale.isDemo ? "Demo" : scale.state.label)
                }
                Toggle("Demo scale (simulated pours)", isOn: $scale.isDemo)
            } footer: {
                Text("A scale connected to GaggiMate can stay there: BrewLog then reads the weight from the machine.")
            }
        }
        .navigationTitle("Scale")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScale) { ScaleConnectSheet() }
    }
}

// MARK: - Machine

/// Which machine BrewLog connects to and how. `showsDone` when it opens as its own sheet (the gear on the machine card).
struct SettingsMachineView: View {
    var showsDone = false
    @Environment(\.dismiss) private var dismiss
    @Environment(MachineManager.self) private var machine
    @Environment(\.espressoSetup) private var espressoSetup
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    @State private var machineHost = MachineManager.shared.host

    var body: some View {
        @Bindable var machine = machine
        @Bindable var espressoSetup = espressoSetup
        let machines = equipment.filter { $0.type == .brewer && $0.method == .espresso }
        Form {
            Section {
                // The espresso machine from Gear, saved with each shot.
                if !machines.isEmpty {
                    Picker("Your machine", selection: $espressoSetup.brewerID) {
                        Text("None").tag(UUID?.none)
                        ForEach(machines, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Picker("Connection", selection: $machine.kind) {
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
                if machine.kind == .decent { DecentMachineRow() }
                if machine.kind == .laMarzocco { LaMarzoccoAccountRow() }
                if machine.kind != .none {
                    LabeledContent("Status", value: machine.stateText)
                }
                if machine.kind.capabilities.contains(.profiles) && machine.kind != .demo {
                    MachineProfileImportRow()
                }
            } footer: {
                Text(connectionHelp)
            }

            // GaggiMate measures the pressure itself; the sensor is for machines BrewLog can't connect to.
            if !machine.readsPressure {
                Section {
                    PressureMonitorRow()
                } header: {
                    Text("Pressure sensor")
                } footer: {
                    Text("For a machine BrewLog can't connect to: a BOOKOO Espresso Monitor over Bluetooth.")
                }
            }
        }
        .navigationTitle("Machine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onDisappear { if machine.host != machineHost, gaggiMateURL(host: machineHost) != nil { machine.host = machineHost } }
    }

    /// One short sentence about the selected connection.
    private var connectionHelp: String {
        switch machine.kind {
        case .gaggimate:
            return "Over your Wi-Fi: pressure, temperature and flow, starting the shot, modes, profiles as recipes. Use the address from GaggiMate's web interface."
        case .laMarzocco:
            return "Through your La Marzocco account and their servers (opt-in): follows the shot, shows the boiler, switches the machine on or to standby and changes the brew temperature."
        case .decent:
            return "Over Bluetooth: pressure, temperature and flow, starting the shot (not with a group head controller) and modes."
        case .demo:
            return "A simulated machine for trying things out."
        case .none:
            return "BrewLog connects one machine at a time. Without one it times the shot with your scale."
        }
    }
}

// MARK: - Shot

struct SettingsShotView: View {
    @Environment(MachineManager.self) private var machine
    @AppStorage(SettingsKey.autoStopShot) private var autoStopShot = true
    @AppStorage(SettingsKey.shotStopLag) private var shotStopLag = 1.0
    @AppStorage(SettingsKey.shotStopLearn) private var shotStopLearn = true
    @AppStorage(SettingsKey.pressureFocus) private var pressureFocus = PressureFocusMode.automatic
    @AppStorage(SettingsKey.landscapeChart) private var landscapeChart = true
    @AppStorage(SettingsKey.steamAfterShot) private var steamAfterShot = SteamAfterShot.ask
    @State private var learnedLags = StopLagLearner.all()

    var body: some View {
        Form {
            Section {
                Toggle("Stop at the target yield", isOn: $autoStopShot)
                if autoStopShot {
                    Toggle("Learn the stop lead", isOn: $shotStopLearn)
                    if shotStopLearn {
                        let learned = learnedLags[StopLagLearner.key(machine: machine.kind, scaleOnMachine: false)]
                            ?? learnedLags[StopLagLearner.key(machine: machine.kind, scaleOnMachine: true)]
                        if let learned {
                            LabeledContent("Stop lead",
                                           value: String(format: "%.1f s · learned from %d shot%@", learned.lag, learned.shots,
                                                         learned.shots == 1 ? "" : "s"))
                            Button("Start learning again", role: .destructive) {
                                StopLagLearner.reset()
                                learnedLags = [:]
                            }
                        } else {
                            LabeledContent("Stop lead", value: String(format: "%.1f s · learns from your next shot", shotStopLag))
                        }
                    } else {
                        VStack(alignment: .leading) {
                            Text("Stop lead \(shotStopLag, specifier: "%.1f") s")
                            Slider(value: $shotStopLag, in: 0.5...2.5, step: 0.1)
                        }
                    }
                }
            } header: {
                Text("Stop at the yield")
            } footer: {
                Text("BrewLog stops the shot when the weight plus the flow times the lead reaches the yield. Learning measures what still drips in after each stop it made and moves the lead halfway towards the right value, per machine and scale.")
            }
            .onAppear { learnedLags = StopLagLearner.all() }

            Section {
                Picker("Pressure view", selection: $pressureFocus) {
                    ForEach(PressureFocusMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Landscape chart", isOn: $landscapeChart)
            } header: {
                Text("Live screen")
            } footer: {
                Text("Pressure view: Automatic shows the big pressure number and graph while a pressure sensor is connected, Always also with the machine's own pressure. Landscape chart: a button on the live chart, and turning the phone, show it full screen.")
            }

            if machine.kind == .gaggimate || machine.kind == .demo {
                Section {
                    Picker("After an espresso", selection: $steamAfterShot) {
                        ForEach(SteamAfterShot.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("After the shot")
                } footer: {
                    Text("Switch the machine off, ask, or leave it on. A milk drink (switch on the Brew tab, or milk in the recipe) goes to steam after the shot and weighs the milk.")
                }
            }
        }
        .navigationTitle("Shot")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Power and smart plug

struct SettingsPowerView: View {
    @Environment(MachineManager.self) private var machine
    @AppStorage(SettingsKey.powerPlug) private var powerPlug = PlugKind.none
    @AppStorage(SettingsKey.powerShortcutOn) private var shortcutOn = "Machine on"
    @AppStorage(SettingsKey.powerShortcutOff) private var shortcutOff = "Machine off"
    @AppStorage(SettingsKey.powerPlugOffInStandby) private var plugOffInStandby = true
    @AppStorage(SettingsKey.powerCountdown) private var powerCountdown = 30.0
    @AppStorage(SettingsKey.powerAutoOff) private var powerAutoOff = 0.0

    var body: some View {
        Form {
            if machine.kind == .gaggimate || machine.kind == .demo {
                Section {
                    Picker("Smart plug", selection: $powerPlug) {
                        ForEach(PlugKind.allCases) { Text($0.title).tag($0) }
                    }
                    if powerPlug == .shortcuts {
                        LabeledContent("Shortcut to switch on") {
                            TextField("Machine on", text: $shortcutOn).multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Shortcut to switch off") {
                            TextField("Machine off", text: $shortcutOff).multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Button("Test on") { ShortcutPlug.test(name: shortcutOn, done: .on) }
                            Spacer()
                            Button("Test off") { ShortcutPlug.test(name: shortcutOff, done: .off) }
                        }
                        .buttonStyle(.borderless)
                        Toggle("Plug off in standby", isOn: $plugOffInStandby)
                        if plugOffInStandby {
                            Picker("Plug off after", selection: $powerCountdown) {
                                Text("Right away").tag(0.0)
                                Text("30 s").tag(30.0)
                                Text("2 min").tag(120.0)
                                Text("5 min").tag(300.0)
                            }
                        }
                    }
                } header: {
                    Text("Smart plug")
                } footer: {
                    Text("Make two shortcuts in the Shortcuts app that switch the plug on and off (from Home, Home Assistant or the plug's app) and enter their names. The Shortcuts app opens for a moment when BrewLog runs one. When the machine goes to standby, the plug goes off after the time you set, with a Cancel button.")
                }
                Section {
                    Picker("Auto-off", selection: $powerAutoOff) {
                        Text("Never").tag(0.0)
                        Text("15 min").tag(900.0)
                        Text("30 min").tag(1800.0)
                        Text("60 min").tag(3600.0)
                    }
                } footer: {
                    Text("Puts the machine into standby after that long without a shot. The plug and auto-off only work while BrewLog is open: a locked phone can't switch anything.")
                }
            } else {
                Section {
                    Text("Switching the machine off and on, the smart plug and auto-off are available for GaggiMate. Choose it under Machine.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Power & smart plug")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Brew assistant

struct SettingsBrewView: View {
    @AppStorage(SettingsKey.autoStartThreshold) private var autoStartThreshold = 1.5
    @AppStorage(SettingsKey.pingLeadMode) private var pingLeadMode = PingLeadMode.auto.rawValue
    @AppStorage(SettingsKey.pingLeadGrams) private var pingLeadGrams = 3.0
    @AppStorage(SettingsKey.reactionTime) private var reactionTime = 0.6
    @AppStorage(SettingsKey.countdownTicks) private var countdownTicks = false
    @AppStorage(SettingsKey.valveCountdown) private var valveCountdown = true
    @AppStorage(SettingsKey.weighBeansFirst) private var weighBeansFirst = true
    @AppStorage(SettingsKey.rinsePaper) private var rinsePaper = true
    @AppStorage(SettingsKey.finishPing) private var finishPing = true
    @AppStorage(SettingsKey.keepAwake) private var keepAwake = true

    var body: some View {
        Form {
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
            } header: {
                Text("Pours")
            } footer: {
                Text("Automatic buffer = your pour rate × reaction time + 1 g, so you hear the ping early enough to stop on target. Raise the reaction time if you often overpour.")
            }

            Section {
                Toggle("3-2-1 ticks before each step", isOn: $countdownTicks)
                if !countdownTicks {
                    Toggle("3-2-1 ticks before opening or closing the valve", isOn: $valveCountdown)
                }
                Toggle("Chime at target brew time", isOn: $finishPing)
            } header: {
                Text("Cues")
            } footer: {
                Text("Valve ticks (Hario Switch) count down to the moment you open or close the valve.")
            }

            Section {
                Toggle("Weigh the beans first", isOn: $weighBeansFirst)
                Toggle("Rinse the paper", isOn: $rinsePaper)
                Toggle("Keep screen on while brewing", isOn: $keepAwake)
            } header: {
                Text("Steps")
            } footer: {
                Text("With a scale connected, a brew can start by weighing the beans (you can skip it).")
            }
        }
        .navigationTitle("Brew assistant")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sound, haptics and voice

struct SettingsSoundView: View {
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = true
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKey.soundVolume) private var soundVolume = 0.8
    @AppStorage(SettingsKey.silentModeSound) private var silentModeSound = true
    @AppStorage(SettingsKey.voicePrompts) private var voicePrompts = false
    @AppStorage(SettingsKey.voicePreview) private var voicePreview = true

    var body: some View {
        Form {
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

            Section {
                Toggle("Spoken step prompts", isOn: $voicePrompts)
                if voicePrompts {
                    Toggle("Announce the next step ahead", isOn: $voicePreview)
                    Button("Test voice") {
                        SoundPlayer.shared.prepare()
                        VoicePrompter.shared.say(StepAnnouncement.text(for: RecipeStep(kind: .bloom, time: 0, target: 45, note: nil)), delay: 0)
                    }
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("Reads each step out loud, e.g. \"Pour to 150 grams.\" With the next step ahead: \"Next, pour to 250 grams.\" \(Int(StepAnnouncement.leadTime)) seconds before it. Uses the volume and silent-mode setting above.")
            }
        }
        .navigationTitle("Sound, haptics & voice")
        .navigationBarTitleDisplayMode(.inline)
        // The sound test buttons start the audio engine, which would keep the app awake in the background.
        .onDisappear { SoundPlayer.shared.stop() }
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

// MARK: - Recipes, backup and data

struct SettingsDataView: View {
    @AppStorage(SettingsKey.onlineRecipes) private var onlineRecipes = true
    private let feed = RecipeFeed.shared

    var body: some View {
        Form {
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

            if Features.askAI { AISettingsSection() }
        }
        .navigationTitle("Recipes, backup & data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
