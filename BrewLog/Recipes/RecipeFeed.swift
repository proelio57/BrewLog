import Foundation
import Observation

/// Online recipe updates: downloads `recipes.json` (same format as `Shared/recipes.json`) from the URL in
/// Info.plist every few hours. New and changed recipes show up without an app update.
/// The last download is cached on the device, so the recipes are also there offline.
@Observable
final class RecipeFeed {
    static let shared = RecipeFeed()

    /// Built-in recipes, updated by the online list (same id = replaced, new id = added).
    private(set) var presets: [Recipe]
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private(set) var isSyncing = false

    @ObservationIgnored private let bundled: [Recipe]
    @ObservationIgnored private let cacheURL: URL

    static let checkInterval: TimeInterval = 6 * 3600
    static let maxDownloadSize = 1024 * 1024
    private static let lastSyncKey = "recipeFeed.lastSync"

    /// From Info.plist (set by CI). Nil or empty = feature off.
    static var feedURL: URL? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: "BrewLogRecipeFeedURL") as? String,
              text.hasPrefix("https://") else { return nil }
        return URL(string: text)
    }

    var isEnabled: Bool { Self.feedURL != nil && UserDefaults.standard.object(forKey: SettingsKey.onlineRecipes) as? Bool ?? true }

    init(bundle: Bundle = .main, cacheDirectory: URL? = nil) {
        let bundled = Self.loadBundled(bundle)
        let directory = cacheDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let cacheURL = directory.appendingPathComponent("recipes-feed.json")
        let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? RecipeFile.decode($0) } ?? []
        self.bundled = bundled
        self.cacheURL = cacheURL
        self.presets = Self.merge(bundled: bundled, remote: cached)
        self.lastSync = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    /// Bundled recipes first (in their order, replaced by newer online versions), then new online recipes.
    static func merge(bundled: [Recipe], remote: [Recipe]) -> [Recipe] {
        var remoteByID: [String: Recipe] = [:]
        for var recipe in remote where !recipe.id.isEmpty {
            recipe.isCustom = nil  // online recipes are presets: not editable, only duplicable
            remoteByID[recipe.id] = recipe
        }
        let bundledIDs = Set(bundled.map(\.id))
        var seen = Set<String>()
        let added = remote.compactMap { remoteByID[$0.id] }
            .filter { !bundledIDs.contains($0.id) && seen.insert($0.id).inserted }
        return bundled.map { remoteByID[$0.id] ?? $0 } + added
    }

    /// Downloads the list if the last check is older than `checkInterval` (or `force`).
    @MainActor
    func syncIfNeeded(force: Bool = false) async {
        guard isEnabled, let url = Self.feedURL, !isSyncing else { return }
        if !force, let lastSync, Date().timeIntervalSince(lastSync) < Self.checkInterval { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            guard data.count <= Self.maxDownloadSize else { throw URLError(.dataLengthExceedsMaximum) }
            let remote = try RecipeFile.decode(data)
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? RecipeFile.encode(remote).write(to: cacheURL, options: .atomic)
            presets = Self.merge(bundled: bundled, remote: remote)
            lastError = nil
            lastSync = Date()
            UserDefaults.standard.set(lastSync, forKey: Self.lastSyncKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func loadBundled(_ bundle: Bundle) -> [Recipe] {
        guard let url = bundle.url(forResource: "recipes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("recipes.json missing from bundle")
            return []
        }
        do {
            return try JSONDecoder().decode([Recipe].self, from: data).map { $0.validated() }
        } catch {
            assertionFailure("Failed to decode recipes.json: \(error)")
            return []
        }
    }
}
