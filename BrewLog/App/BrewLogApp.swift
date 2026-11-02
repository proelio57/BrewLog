import SwiftUI
import SwiftData

@main
struct BrewLogApp: App {
    let container: ModelContainer
    @State private var setup = BrewSetup()
    @State private var espressoSetup = BrewSetup(scope: .espresso)
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
                .environment(\.espressoSetup, espressoSetup)
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
    /// Set by the widgets' brewlog://start: the Brew tab starts the brew as soon as it's shown.
    var startBrewRequested = false

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
    var beanID: UUID? { didSet { save(beanID, "beanID") } }
    var brewerID: UUID? { didSet { save(brewerID, "brewerID") } }
    var grinderID: UUID? { didSet { save(grinderID, "grinderID") } }
    var filterID: UUID? { didSet { save(filterID, "filterID") } }
    var waterID: UUID? { didSet { save(waterID, "waterID") } }
    /// Pour-over or espresso: each remembers its own recipe, bean and gear.
    let scope: SetupScope
    @ObservationIgnored private let defaults: UserDefaults
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

    init(scope: SetupScope = .pourOver, defaults: UserDefaults = .standard) {
        self.scope = scope
        self.defaults = defaults
        let espresso = scope == .espresso
        let recipe = RecipeLibrary.preset(id: defaults.string(forKey: scope.key("recipeID")) ?? "")
            ?? RecipeLibrary.presets.first { $0.method.isEspresso == espresso }
            ?? RecipeLibrary.presets.first
            ?? RecipeLibrary.blankRecipe()
        self.recipe = recipe
        self.dose = recipe.dose
        self.waterTemp = recipe.temperature
        func load(_ name: String) -> UUID? { defaults.string(forKey: scope.key(name)).flatMap(UUID.init(uuidString:)) }
        self.beanID = load("beanID")
        self.brewerID = load("brewerID")
        self.grinderID = load("grinderID")
        self.filterID = load("filterID")
        self.waterID = load("waterID")
    }

    /// The key under which this setup remembers its recipe (custom recipes are restored from it at launch).
    var recipeIDKey: String { scope.key("recipeID") }

    var scaledRecipe: Recipe { recipe.scaled(toDose: dose) }

    func select(_ recipe: Recipe) {
        self.recipe = recipe
        dose = recipe.dose
        waterTemp = recipe.temperature
        defaults.set(recipe.id, forKey: recipeIDKey)
    }

    private func save(_ id: UUID?, _ name: String) {
        defaults.set(id?.uuidString, forKey: scope.key(name))
    }
}

extension BrewSetup {
    /// Before the Filter | Espresso switch an espresso recipe could sit in the pour-over setup: hand it (with its
    /// gear and bean, where espresso has none yet) to the espresso setup and give pour-over a pour-over recipe.
    /// Returns whether something moved, so the Brew tab can open on Espresso.
    @discardableResult
    static func moveEspressoRecipe(from pourOver: BrewSetup, to espresso: BrewSetup) -> Bool {
        guard pourOver.recipe.method.isEspresso else { return false }
        espresso.select(pourOver.recipe)
        espresso.dose = pourOver.dose
        if espresso.grinderID == nil { espresso.grinderID = pourOver.grinderID }
        if espresso.beanID == nil { espresso.beanID = pourOver.beanID }
        if espresso.grindValue == nil { espresso.grindValue = pourOver.grindValue }
        pourOver.select(RecipeLibrary.presets.first { !$0.method.isEspresso } ?? RecipeLibrary.blankRecipe())
        return true
    }
}

/// Which brew setup: pour-over keeps today's `setup.*` keys, espresso has its own `espresso.*` keys.
enum SetupScope {
    case pourOver, espresso

    var keyPrefix: String { self == .pourOver ? "setup." : "espresso." }

    func key(_ name: String) -> String { keyPrefix + name }
}

private struct EspressoSetupKey: EnvironmentKey {
    static let defaultValue = BrewSetup(scope: .espresso)
}

extension EnvironmentValues {
    /// The espresso setup; `BrewSetup` in the environment is the pour-over one.
    var espressoSetup: BrewSetup {
        get { self[EspressoSetupKey.self] }
        set { self[EspressoSetupKey.self] = newValue }
    }
}
