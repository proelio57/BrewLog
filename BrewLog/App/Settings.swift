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
    static let pressureEnabled = "pressure.enabled"
    static let pressureDemo = "pressure.demo"

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
            SettingsKey.finishPing: true,
            SettingsKey.voicePrompts: false,
            SettingsKey.voicePreview: true,
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
    static var valveCountdown: Bool { d.bool(forKey: SettingsKey.valveCountdown) }
    static var weighBeansFirst: Bool { d.bool(forKey: SettingsKey.weighBeansFirst) }
    static var finishPing: Bool { d.bool(forKey: SettingsKey.finishPing) }
    static var voicePrompts: Bool { d.bool(forKey: SettingsKey.voicePrompts) }
    static var voicePreview: Bool { d.bool(forKey: SettingsKey.voicePreview) }
    static var keepAwake: Bool { d.bool(forKey: SettingsKey.keepAwake) }
}
