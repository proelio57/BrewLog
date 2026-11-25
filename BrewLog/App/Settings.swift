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
    static let accentColor = "appearance.accent"
    static let appearance = "appearance.mode"
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
    static let milkTiming = "milk.timing"
    /// Smart plug of the espresso machine (`PlugKind`), the two shortcuts, and when it goes off.
    static let powerPlug = "power.plug"
    static let powerShortcutOn = "power.shortcutOn"
    static let powerShortcutOff = "power.shortcutOff"
    static let powerPlugOffInStandby = "power.plugOffInStandby"
    static let powerCountdown = "power.countdown"
    static let powerAutoOff = "power.autoOff"
    static let autoStopShot = "autoStopShot"
    static let shotStopLag = "shotStopLag"
    /// Learn the stop lead from each shot the app stops (`StopLagLearner`).
    static let shotStopLearn = "shotStopLearn"
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
            SettingsKey.shotStopLearn: true,
            SettingsKey.pressureFocus: PressureFocusMode.automatic.rawValue,
            SettingsKey.landscapeChart: true,
            SettingsKey.steamAfterShot: SteamAfterShot.ask.rawValue,
            SettingsKey.milkTiming: MilkTiming.after.rawValue,
            SettingsKey.powerPlug: PlugKind.none.rawValue,
            SettingsKey.powerShortcutOn: "Machine on",
            SettingsKey.powerShortcutOff: "Machine off",
            SettingsKey.powerPlugOffInStandby: true,
            SettingsKey.powerCountdown: 30.0,
            SettingsKey.powerAutoOff: 0.0,
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
    static var shotStopLearn: Bool { d.bool(forKey: SettingsKey.shotStopLearn) }
}

/// The Brew tab's switch: pour-over (filter) or espresso, each with its own setup.
enum BrewMode: String, CaseIterable, Identifiable {
    case filter, espresso
    var id: String { rawValue }
    var title: String { self == .filter ? "Filter" : "Espresso" }

    /// The mode a recipe belongs to.
    static func of(_ recipe: Recipe) -> BrewMode { recipe.method.isEspresso ? .espresso : .filter }
}

/// Settings → After an espresso: what happens after a shot without milk. A milk drink (the recipe has milk)
/// always switches the machine to steam. (Stored under the old key; the old "steam" value reads as `ask`.)
enum SteamAfterShot: String, CaseIterable, Identifiable {
    /// Ask whether to switch off.
    case ask
    /// Switch the machine off (standby, then the smart plug).
    case switchOff
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Ask to switch off"
        case .switchOff: return "Switch off"
        case .off: return "Nothing"
        }
    }

    static var current: SteamAfterShot {
        UserDefaults.standard.string(forKey: SettingsKey.steamAfterShot).flatMap(SteamAfterShot.init) ?? .ask
    }
}

/// Settings → Shot → Weigh the milk: when the milk of a milk drink is weighed.
enum MilkTiming: String, CaseIterable, Identifiable {
    /// After the shot, while the machine heats up for steam.
    case after
    /// Before the shot: pitcher on the scale first, then the shot.
    case before

    var id: String { rawValue }

    var title: String {
        switch self {
        case .after: return "After the shot"
        case .before: return "Before the shot"
        }
    }

    static var current: MilkTiming {
        UserDefaults.standard.string(forKey: SettingsKey.milkTiming).flatMap(MilkTiming.init) ?? .after
    }
}

/// What BrewLog does with the machine when a shot is done.
enum AfterShot: Equatable {
    /// Milk drink: switch to steam and weigh the milk.
    case steamAndMilk
    /// Milk drink whose milk was weighed before the shot: only switch to steam.
    case steam
    /// Milk drink on a machine BrewLog can't switch: only weigh the milk.
    case milk
    case askSwitchOff
    case switchOff
    case nothing

    static func action(milkDrink: Bool, canSteam: Bool, canSwitchOff: Bool, setting: SteamAfterShot,
                       milkTiming: MilkTiming = .after) -> AfterShot {
        if milkDrink {
            if milkTiming == .before { return canSteam ? .steam : .nothing }
            return canSteam ? .steamAndMilk : .milk
        }
        guard canSwitchOff else { return .nothing }
        switch setting {
        case .ask: return .askSwitchOff
        case .switchOff: return .switchOff
        case .off: return .nothing
        }
    }
}
