import Foundation

/// The notes of the installed release (`whats-new.json`, written by CI from the release notes), and when to show them.
struct WhatsNew: Decodable, Equatable {
    var version: String
    var ios: [String]

    static let seenKey = "whatsNew.lastSeenVersion"

    static func load(bundle: Bundle = .main) -> WhatsNew? {
        guard let url = bundle.url(forResource: "whats-new", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WhatsNew.self, from: data)
    }

    /// The notes to show after an update, or nil. Shown once per version, only when the release changed something
    /// on iOS, and not on a fresh install (onboarding not finished) or for a build whose notes belong to another version.
    static func pending(_ notes: WhatsNew?, installedVersion: String, lastSeen: String?, onboardingDone: Bool) -> WhatsNew? {
        guard let notes, notes.version == installedVersion, lastSeen != installedVersion else { return nil }
        guard onboardingDone else { return nil }
        return notes.ios.isEmpty ? nil : notes
    }
}
