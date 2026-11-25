import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BrewSetup.self) private var setup
    @Environment(\.espressoSetup) private var espressoSetup
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var savedRecipes: [SavedRecipe]
    private let power = MachinePower.shared

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            BrewSetupView()
                .tabItem { Label("Brew", systemImage: "drop.circle.fill") }
                .tag(AppTab.brew)
            RecipeListView()
                .tabItem { Label("Recipes", systemImage: "book.closed.fill") }
                .tag(AppTab.recipes)
            HistoryListView()
                .tabItem { Label("Journal", systemImage: "list.bullet.rectangle.portrait.fill") }
                .tag(AppTab.history)
            BeanListView()
                .tabItem { Label("Beans", systemImage: "leaf.fill") }
                .tag(AppTab.beans)
            GearListView()
                .tabItem { Label("Gear", systemImage: "wrench.and.screwdriver.fill") }
                .tag(AppTab.gear)
        }
        .overlay(alignment: .top) { PowerBanner(power: power).allowsHitTesting(power.secondsLeft != nil) }
        .alert("Smart plug", isPresented: Binding(get: { power.shortcutError != nil },
                                                  set: { if !$0 { power.shortcutError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(power.shortcutError ?? "")
        }
        .alert("Done steaming?", isPresented: Bindable(power).askSwitchOff) {
            Button("Switch off") { power.switchOff() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Switch the machine off: standby, and the smart plug if you set one up.")
        }
        .fullScreenCover(item: $router.cover) { cover in
            Group {
                switch cover {
                case .onboarding:
                    OnboardingView(onFinish: { router.present(nil) },
                                   onJustWeigh: { router.present(.quickWeigh) })
                case .quickWeigh:
                    QuickWeighView()
                case .whatsNew:
                    if let notes = WhatsNew.load() {
                        WhatsNewView(notes: notes) { router.present(nil) }
                    }
                }
            }
            .appTint()
        }
        .task {
            // Unit tests run inside the app: don't touch Bluetooth or show onboarding.
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            restoreCustomRecipe()
            BrewLiveActivity.endAll()
            ScaleManager.shared.start()
            MachineManager.shared.start()
            MachinePower.shared.start()
            PressureMonitor.shared.start()
            if !UserDefaults.standard.bool(forKey: SettingsKey.onboardingDone) {
                router.cover = .onboarding
            } else if showWhatsNew() {
                router.cover = .whatsNew
            }
            WidgetSync.update(context: context, pourOver: setup, espresso: espressoSetup)
            await RecipeFeed.shared.syncIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            if phase == .background {
                WidgetSync.update(context: context, pourOver: setup, espresso: espressoSetup)
                GitSync.shared.syncIfEnabled(context: context)
                return
            }
            guard phase == .active else { return }
            Task { await RecipeFeed.shared.syncIfNeeded() }
        }
        // Widgets open the app with brewlog://brew, …/start, …/weigh, …/journal or …/beans.
        .onOpenURL { url in
            guard let link = AppLink(url: url) else { return }
            switch link {
            case .brew: router.tab = .brew
            case .start:
                router.tab = .brew
                router.startBrewRequested = true
            case .journal: router.tab = .history
            case .beans: router.tab = .beans
            case .weigh:
                router.tab = .brew
                router.present(.quickWeigh)
            case .resume:
                if let failure = ShortcutPlug.failure(in: url) {
                    power.shortcutFailed(name: failure.name, message: failure.message)
                } else if let done = ShortcutPlug.success(in: url) {
                    power.plugSwitched(on: done == .on)
                }
            }
        }
    }

    /// After an update that changed something on iOS: remembers the version so it shows once.
    private func showWhatsNew() -> Bool {
        let d = UserDefaults.standard
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let pending = WhatsNew.pending(WhatsNew.load(), installedVersion: version, lastSeen: d.string(forKey: WhatsNew.seenKey),
                                       onboardingDone: d.bool(forKey: SettingsKey.onboardingDone))
        d.set(version, forKey: WhatsNew.seenKey)
        return pending != nil
    }

    /// Own recipes aren't presets, so each setup (pour-over and espresso) gets its own back from the store.
    private func restoreCustomRecipe() {
        for setup in [setup, espressoSetup] {
            guard let id = UserDefaults.standard.string(forKey: setup.recipeIDKey),
                  RecipeLibrary.preset(id: id) == nil,
                  let recipe = savedRecipes.first(where: { $0.id == id })?.recipe else { continue }
            setup.select(recipe)
        }
        // An own espresso recipe from before the Filter | Espresso switch belongs to the espresso setup.
        if BrewSetup.moveEspressoRecipe(from: setup, to: espressoSetup) {
            UserDefaults.standard.set(BrewMode.espresso.rawValue, forKey: SettingsKey.brewMode)
        }
    }
}
