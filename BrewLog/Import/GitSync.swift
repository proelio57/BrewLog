import Foundation
import Observation
import Security
import SwiftData
import UIKit

/// Secrets (Git token, AI key) in the Keychain, only readable on this device while unlocked.
enum Keychain {
    static func get(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "BrewLog",
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "BrewLog",
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// Keeps the backup in a Git repository: downloads and merges what other devices pushed, then commits this
/// device's state when something changed (see `GitRemote`).
@MainActor
@Observable
final class GitSync {
    static let shared = GitSync()
    static let tokenAccount = "git.token"

    private enum Key {
        static let remote = "git.remote"
        static let auto = "git.auto"
        static let photos = "git.photos"
        static let lastSync = "git.lastSync"
        static let lastHash = "git.lastHash"
        static let lastSHA = "git.lastSHA"
    }

    var remote: GitRemote { didSet { save(remote) } }
    var autoSync: Bool { didSet { defaults.set(autoSync, forKey: Key.auto) } }
    var includePhotos: Bool { didSet { defaults.set(includePhotos, forKey: Key.photos) } }
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var message: String?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    private init() {
        let stored = UserDefaults.standard
        remote = stored.data(forKey: Key.remote).flatMap { try? JSONDecoder().decode(GitRemote.self, from: $0) } ?? GitRemote()
        autoSync = stored.bool(forKey: Key.auto)
        includePhotos = stored.bool(forKey: Key.photos)
        lastSync = stored.object(forKey: Key.lastSync) as? Date
    }

    var hasToken: Bool { Keychain.get(Self.tokenAccount) != nil }
    var isConfigured: Bool { remote.isValid && hasToken }

    func setToken(_ token: String?) {
        Keychain.set(token?.trimmingCharacters(in: .whitespacesAndNewlines), for: Self.tokenAccount)
        // A new token or repository starts fresh.
        defaults.removeObject(forKey: Key.lastSHA)
        defaults.removeObject(forKey: Key.lastHash)
    }

    private func save(_ remote: GitRemote) {
        defaults.set(try? JSONEncoder().encode(remote), forKey: Key.remote)
        defaults.removeObject(forKey: Key.lastSHA)
        defaults.removeObject(forKey: Key.lastHash)
    }

    /// After a brew or when the app goes to the background, if turned on. At most every 2 minutes.
    func syncIfEnabled(context: ModelContext) {
        guard autoSync, isConfigured, !isSyncing else { return }
        if let lastSync, Date().timeIntervalSince(lastSync) < 120 { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "Git backup")
        Task {
            await sync(context: context)
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    enum SyncError: LocalizedError {
        case notConfigured, unauthorized, notFound, tooLarge, server(Int, String?)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Set up the repository and token first."
            case .unauthorized: return "The token was refused. Check that it may read and write this repository."
            case .notFound: return "Repository or branch not found (or the token can't see it)."
            case .tooLarge: return "The backup is too large for the file API. Turn off photos."
            case .server(let code, let text): return "Server error \(code)" + (text.map { ": \($0)" } ?? ".")
            }
        }
    }

    /// Download and merge, then commit this device's backup if it changed.
    @discardableResult
    func sync(context: ModelContext) async -> Bool {
        guard !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            var result = try await syncOnce(context: context)
            if result == nil { result = try await syncOnce(context: context) } // the file changed in between: once more
            message = result ?? "Someone else is writing to the file right now. Try again in a moment."
            lastSync = Date()
            defaults.set(lastSync, forKey: Key.lastSync)
            return result != nil
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    /// nil when the write conflicted with a newer commit.
    private func syncOnce(context: ModelContext) async throws -> String? {
        guard let token = Keychain.get(Self.tokenAccount), remote.isValid else { throw SyncError.notConfigured }
        let remote = self.remote

        // 1. What's in the repository? Merge it in (adds what's new, never deletes).
        var sha: String?
        var imported = 0
        guard let metadata = remote.metadataRequest(token: token) else { throw SyncError.notConfigured }
        let (metaData, metaResponse) = try await load(metadata, allow404: true)
        if metaResponse.statusCode != 404 {
            sha = GitRemote.blobSHA(from: metaData)
            if sha != defaults.string(forKey: Key.lastSHA), let raw = remote.rawRequest(token: token) {
                let (file, _) = try await load(raw, allow404: false)
                if file.count > DataImporter.maxFileSize { throw SyncError.tooLarge }
                let summary = try DataImporter.importData(file, into: context)
                imported = summary.brews + summary.beans + summary.grinders + summary.brewers + summary.recipesAdded
            }
        }

        // 2. Commit this device's state if it changed since the last sync.
        let stable = try DataImporter.exportBackup(from: context, exportedAt: Date(timeIntervalSince1970: 0),
                                                   includePhotos: includePhotos, pretty: true)
        let hash = ContentHash.fnv1a(stable)
        if sha != nil, sha == defaults.string(forKey: Key.lastSHA), hash == defaults.string(forKey: Key.lastHash) {
            return imported > 0 ? "Added \(imported) items from the repository." : "Up to date."
        }
        let content = try DataImporter.exportBackup(from: context, includePhotos: includePhotos, pretty: true)
        // GitHub's and GitLab's file APIs take files up to about 100 MB, base64 makes them a third larger.
        if content.count > 70_000_000 { throw SyncError.tooLarge }
        let brews = (try? context.fetchCount(FetchDescriptor<Brew>())) ?? 0
        let message = "BrewLog backup: \(brews) brew\(brews == 1 ? "" : "s")"
        guard let write = remote.writeRequest(content: content, sha: sha, message: message, token: token) else {
            throw SyncError.notConfigured
        }
        let (_, writeResponse) = try await load(write, allow404: false, conflictIsNil: true)
        if writeResponse.statusCode == 409 || writeResponse.statusCode == 422 { return nil }

        // 3. Remember what was written, so the next sync knows whether anything changed.
        let (after, afterResponse) = try await load(metadata, allow404: true)
        if afterResponse.statusCode == 200, let newSHA = GitRemote.blobSHA(from: after) {
            defaults.set(newSHA, forKey: Key.lastSHA)
            defaults.set(hash, forKey: Key.lastHash)
        }
        return imported > 0 ? "Added \(imported) items and saved the backup." : "Backup saved to \(remote.repository)."
    }

    private func load(_ request: URLRequest, allow404: Bool, conflictIsNil: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.server(0, nil) }
        switch http.statusCode {
        case 200...299: return (data, http)
        case 401, 403: throw SyncError.unauthorized
        case 404 where allow404: return (data, http)
        case 404: throw SyncError.notFound
        case 409 where conflictIsNil, 422 where conflictIsNil: return (data, http)
        case 413: throw SyncError.tooLarge
        default: throw SyncError.server(http.statusCode, GitRemote.errorMessage(from: data))
        }
    }
}
