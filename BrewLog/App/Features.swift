/// Features that are built but switched off in the UI.
enum Features {
    /// "Ask Claude" (bean advice): hidden for now while the AI connection is reworked (other providers, sign-in).
    /// The code stays (`BeanAdvisor`, `BeanAdviceView`, `AISettingsSection`); set this to `true` to show it again.
    /// Same switch on Android: `Features.askAi`.
    static let askAI = false

    /// Temporary test whether HomeKit works in a SideStore install (Settings → Espresso machine → HomeKit test).
    static let homeKitTest = true
}
