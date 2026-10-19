import SwiftUI
import SwiftData

@main
struct BrewLogApp: App {
    let container: ModelContainer
    @State private var setup = BrewSetup()
    @State private var router = AppRouter()

    init() {
        AppSettings.registerDefaults()
        do {
            container = try ModelContainer(for: Bean.self, Equipment.self, Brew.self, SavedRecipe.self)
        } catch {
            fatalError("Could not create the data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(setup)
                .environment(router)
                .environment(ScaleManager.shared)
                .environment(MachineManager.shared)
                .environment(PressureMonitor.shared)
        }
        .modelContainer(container)
    }
}

enum AppTab: Hashable {
    case brew, recipes, history, beans, gear
}

/// Full-screen flows presented above the tabs.
enum RootCover: String, Identifiable {
    case onboarding, quickWeigh
    var id: String { rawValue }
}

@Observable
final class AppRouter {
    var tab: AppTab = .brew
    var cover: RootCover?

    /// Switches between full-screen flows (dismiss first, then present, to avoid presentation glitches).
    func present(_ next: RootCover?) {
        guard cover != nil else {
            cover = next
            return
        }
        cover = nil
        guard let next else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.cover = next }
    }
}

/// The brew being configured on the Brew tab. Remembers your last choices.
@Observable
final class BrewSetup {
    var recipe: Recipe
    var dose: Double
    var waterTemp: Double
    var beanID: UUID? { didSet { save(beanID, SettingsKey.lastBeanID) } }
    var brewerID: UUID? { didSet { save(brewerID, SettingsKey.lastBrewerID) } }
    var grinderID: UUID? { didSet { save(grinderID, SettingsKey.lastGrinderID) } }
    var filterID: UUID? { didSet { save(filterID, SettingsKey.lastFilterID) } }
    var waterID: UUID? { didSet { save(waterID, SettingsKey.lastWaterID) } }
    var grindValue: Double?
    var grindText: String = ""
    /// Bean + grinder for which the grind was set explicitly (setup assistant, "Brew again").
    /// History-based recommendations don't overwrite it until the bean or grinder changes.
    private(set) var pinnedGrindContext: String?

    var grindContextKey: String {
        "\(beanID?.uuidString ?? "-")|\(grinderID?.uuidString ?? "-")"
    }

    /// Sets the grind explicitly so it isn't replaced by a recommendation for the current bean + grinder.
    func pinGrind(_ value: Double?) {
        grindValue = value
        pinnedGrindContext = grindContextKey
        rememberGrind()
    }

    var isGrindPinned: Bool { pinnedGrindContext == grindContextKey }

    @ObservationIgnored private var grindMemory = GrindMemory.load()

    /// Remembers the grind set by hand for the selected grinder (see `GrindMemory`).
    func rememberGrind() {
        guard let grinderID, let grindValue else { return }
        grindMemory.remember(grindValue, grinder: grinderID)
        grindMemory.save()
    }

    /// After switching grinders: that grinder's own setting, never the number from the previous grinder's scale.
    func restoreGrind(for grinder: Equipment?, recommendation: GrindRecommendation?, lastBrew: Date?) {
        // A grind set explicitly together with the grinder ("Brew again", setup assistant) stays.
        guard !isGrindPinned else { return }
        guard let grinder else {
            grindValue = nil
            return
        }
        grindValue = grindMemory.grind(for: grinder.id, spec: grinder.grinderSpec, recommendation: recommendation?.value,
                                       lastBrew: lastBrew, espresso: recipe.method.isEspresso)
    }

    init() {
        let defaults = UserDefaults.standard
        let recipe = RecipeLibrary.preset(id: defaults.string(forKey: SettingsKey.lastRecipeID) ?? "")
            ?? RecipeLibrary.presets.first
            ?? RecipeLibrary.blankRecipe()
        self.recipe = recipe
        self.dose = recipe.dose
        self.waterTemp = recipe.temperature
        func load(_ key: String) -> UUID? { defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) }
        self.beanID = load(SettingsKey.lastBeanID)
        self.brewerID = load(SettingsKey.lastBrewerID)
        self.grinderID = load(SettingsKey.lastGrinderID)
        self.filterID = load(SettingsKey.lastFilterID)
        self.waterID = load(SettingsKey.lastWaterID)
    }

    var scaledRecipe: Recipe { recipe.scaled(toDose: dose) }

    func select(_ recipe: Recipe) {
        self.recipe = recipe
        dose = recipe.dose
        waterTemp = recipe.temperature
        UserDefaults.standard.set(recipe.id, forKey: SettingsKey.lastRecipeID)
    }

    private func save(_ id: UUID?, _ key: String) {
        UserDefaults.standard.set(id?.uuidString, forKey: key)
    }
}
