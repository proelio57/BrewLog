import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BrewSetup.self) private var setup
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var savedRecipes: [SavedRecipe]

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
        .fullScreenCover(item: $router.cover) { cover in
            switch cover {
            case .onboarding:
                OnboardingView(onFinish: { router.present(nil) },
                               onJustWeigh: { router.present(.quickWeigh) })
            case .quickWeigh:
                QuickWeighView()
            }
        }
        .task {
            // Unit tests run inside the app: don't touch Bluetooth or show onboarding.
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            restoreCustomRecipe()
            BrewLiveActivity.endAll()
            ScaleManager.shared.start()
            MachineManager.shared.start()
            PressureMonitor.shared.start()
            if !UserDefaults.standard.bool(forKey: SettingsKey.onboardingDone) {
                router.cover = .onboarding
            }
            WidgetSync.update(context: context, selectedBeanID: setup.beanID)
            await RecipeFeed.shared.syncIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            if phase == .background {
                WidgetSync.update(context: context, selectedBeanID: setup.beanID)
                GitSync.shared.syncIfEnabled(context: context)
                return
            }
            guard phase == .active else { return }
            Task { await RecipeFeed.shared.syncIfNeeded() }
        }
        // Widgets open the app with brewlog://brew, …/weigh, …/journal or …/beans.
        .onOpenURL { url in
            guard let link = AppLink(url: url) else { return }
            switch link {
            case .brew: router.tab = .brew
            case .journal: router.tab = .history
            case .beans: router.tab = .beans
            case .weigh:
                router.tab = .brew
                router.present(.quickWeigh)
            }
        }
    }

    private func restoreCustomRecipe() {
        guard let id = UserDefaults.standard.string(forKey: SettingsKey.lastRecipeID),
              RecipeLibrary.preset(id: id) == nil,
              let recipe = savedRecipes.first(where: { $0.id == id })?.recipe else { return }
        setup.select(recipe)
    }
}
