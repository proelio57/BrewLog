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
    static let finishPing = "finishPing"
    static let keepAwake = "keepAwake"
    static let onboardingDone = "onboardingDone"
    static let setupBannerDismissed = "setupBannerDismissed"
    static let quickWeighAutoStart = "quickWeighAutoStart"
    static let chartShowsFlow = "chartShowsFlow"
    static let onlineRecipes = "onlineRecipes"
    static let machineKind = "machine.kind"
    static let machineHost = "machine.host"

    // Last used setup
    static let lastRecipeID = "setup.recipeID"
    static let lastBrewerID = "setup.brewerID"
    static let lastGrinderID = "setup.grinderID"
    static let lastFilterID = "setup.filterID"
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
            SettingsKey.finishPing: true,
            SettingsKey.keepAwake: true,
            SettingsKey.quickWeighAutoStart: true,
            SettingsKey.chartShowsFlow: true,
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
    static var finishPing: Bool { d.bool(forKey: SettingsKey.finishPing) }
    static var keepAwake: Bool { d.bool(forKey: SettingsKey.keepAwake) }
}
