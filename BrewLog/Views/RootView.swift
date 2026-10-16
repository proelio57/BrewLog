import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BrewSetup.self) private var setup
    @Environment(\.scenePhase) private var scenePhase
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
            if !UserDefaults.standard.bool(forKey: SettingsKey.onboardingDone) {
                router.cover = .onboarding
            }
            await RecipeFeed.shared.syncIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            Task { await RecipeFeed.shared.syncIfNeeded() }
        }
    }

    private func restoreCustomRecipe() {
        guard let id = UserDefaults.standard.string(forKey: SettingsKey.lastRecipeID),
              RecipeLibrary.preset(id: id) == nil,
              let recipe = savedRecipes.first(where: { $0.id == id })?.recipe else { return }
        setup.select(recipe)
    }
}
