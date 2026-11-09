import Foundation

enum SettingsKey {
    static let demoScale = "demoScale"
    static let autoStartThreshold = "autoStartThreshold"
    static let pingLeadMode = "pingLeadMode"
    static let pingLeadGrams = "pingLeadGrams"
    static let reactionTime = "reactionTime"
    static let soundEnabled = "soundEnabled"
    static let hapticsEnabled = "hapticsEnabled"
    static let soundVolume = "soundVolume"
    static let silentModeSound = "silentModeSound"
    static let countdownTicks = "countdownTicks"
    static let valveCountdown = "valveCountdown"
    static let weighBeansFirst = "weighBeansFirst"
    static let rinsePaper = "rinsePaper"
    static let finishPing = "finishPing"
    static let voicePrompts = "voicePrompts"
    static let voicePreview = "voicePreview"
    static let keepAwake = "keepAwake"
    static let onboardingDone = "onboardingDone"
    static let setupBannerDismissed = "setupBannerDismissed"
    static let quickWeighAutoStart = "quickWeighAutoStart"
    static let chartShowsFlow = "chartShowsFlow"
    static let onlineRecipes = "onlineRecipes"
    static let recipeFilter = "recipes.filter"
    static let aiWebSearch = "ai.webSearch"
    static let machineKind = "machine.kind"
    static let machineHost = "machine.host"
    /// The paired Decent DE1 (CoreBluetooth peripheral identifier).
    static let machineDecentID = "machine.decentID"
    static let pressureEnabled = "pressure.enabled"
    static let pressureDemo = "pressure.demo"
    static let pressureFocus = "pressure.focus"
    static let landscapeChart = "chart.landscape"
    static let steamAfterShot = "machine.steamAfterShot"
    static let autoStopShot = "autoStopShot"
    static let shotStopLag = "shotStopLag"
    static let brewMode = "brewMode"

    // Last used setup
    static let lastRecipeID = "setup.recipeID"
    static let lastBrewerID = "setup.brewerID"
    static let lastGrinderID = "setup.grinderID"
    static let lastFilterID = "setup.filterID"
    static let lastWaterID = "setup.waterID"
    static let lastBeanID = "setup.beanID"
}

enum PingLeadMode: String, CaseIterable, Identifiable {
    case auto, fixed
    var id: String { rawValue }
    var title: String { self == .auto ? "Automatic (flow based)" : "Fixed grams" }
}

/// Typed access to user settings with sensible defaults.
enum AppSettings {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.autoStartThreshold: 1.5,
            SettingsKey.pingLeadMode: PingLeadMode.auto.rawValue,
            SettingsKey.pingLeadGrams: 3.0,
            SettingsKey.reactionTime: 0.6,
            SettingsKey.soundEnabled: true,
            SettingsKey.hapticsEnabled: true,
            SettingsKey.soundVolume: 0.8,
            SettingsKey.silentModeSound: true,
            SettingsKey.countdownTicks: false,
            SettingsKey.valveCountdown: true,
            SettingsKey.weighBeansFirst: true,
            SettingsKey.rinsePaper: true,
            SettingsKey.finishPing: true,
            SettingsKey.voicePrompts: false,
            SettingsKey.voicePreview: true,
            SettingsKey.keepAwake: true,
            SettingsKey.quickWeighAutoStart: true,
            SettingsKey.chartShowsFlow: true,
            SettingsKey.autoStopShot: true,
            SettingsKey.shotStopLag: 1.0,
            SettingsKey.pressureFocus: PressureFocusMode.automatic.rawValue,
            SettingsKey.landscapeChart: true,
            SettingsKey.steamAfterShot: SteamAfterShot.ask.rawValue,
        ])
    }

    private static var d: UserDefaults { .standard }

    static var autoStartThreshold: Double { d.double(forKey: SettingsKey.autoStartThreshold) }
    static var pingLeadMode: PingLeadMode { PingLeadMode(rawValue: d.string(forKey: SettingsKey.pingLeadMode) ?? "") ?? .auto }
    static var pingLeadGrams: Double { d.double(forKey: SettingsKey.pingLeadGrams) }
    static var reactionTime: Double { d.double(forKey: SettingsKey.reactionTime) }
    static var soundEnabled: Bool { d.bool(forKey: SettingsKey.soundEnabled) }
    static var hapticsEnabled: Bool { d.bool(forKey: SettingsKey.hapticsEnabled) }
    static var soundVolume: Double { d.double(forKey: SettingsKey.soundVolume) }
    static var silentModeSound: Bool { d.bool(forKey: SettingsKey.silentModeSound) }
    static var countdownTicks: Bool { d.bool(forKey: SettingsKey.countdownTicks) }
    static var valveCountdown: Bool { d.bool(forKey: SettingsKey.valveCountdown) }
    static var weighBeansFirst: Bool { d.bool(forKey: SettingsKey.weighBeansFirst) }
    static var rinsePaper: Bool { d.bool(forKey: SettingsKey.rinsePaper) }
    static var finishPing: Bool { d.bool(forKey: SettingsKey.finishPing) }
    static var voicePrompts: Bool { d.bool(forKey: SettingsKey.voicePrompts) }
    static var voicePreview: Bool { d.bool(forKey: SettingsKey.voicePreview) }
    static var keepAwake: Bool { d.bool(forKey: SettingsKey.keepAwake) }
    /// Espresso: stop the shot (or say "Stop now") just before the target yield.
    static var autoStopShot: Bool { d.bool(forKey: SettingsKey.autoStopShot) }
    /// Seconds of flow still on its way to the cup after the stop (0.5–2.5 s).
    static var shotStopLag: Double { min(max(d.double(forKey: SettingsKey.shotStopLag), 0.5), 2.5) }
}

/// The Brew tab's switch: pour-over (filter) or espresso, each with its own setup.
enum BrewMode: String, CaseIterable, Identifiable {
    case filter, espresso
    var id: String { rawValue }
    var title: String { self == .filter ? "Filter" : "Espresso" }

    /// The mode a recipe belongs to.
    static func of(_ recipe: Recipe) -> BrewMode { recipe.method.isEspresso ? .espresso : .filter }
}

/// Settings → After the shot: switch the machine to steam for milk.
enum SteamAfterShot: String, CaseIterable, Identifiable {
    /// Ask when the shot is done.
    case ask
    /// Switch straight away.
    case steam
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Ask"
        case .steam: return "Switch to steam"
        case .off: return "Off"
        }
    }

    static var current: SteamAfterShot {
        UserDefaults.standard.string(forKey: SettingsKey.steamAfterShot).flatMap(SteamAfterShot.init) ?? .ask
    }
}
