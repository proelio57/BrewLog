import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where the backup is kept in a Git repository: GitHub, GitLab or Gitea / Forgejo, written with their file APIs
/// (one commit per backup, so the history of your journal stays in Git). The token is stored in the Keychain.
struct GitRemote: Codable, Equatable {
    enum Provider: String, Codable, CaseIterable, Identifiable {
        case github, gitlab, gitea
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .github: return "GitHub"
            case .gitlab: return "GitLab"
            case .gitea: return "Gitea / Forgejo"
            }
        }
        var defaultHost: String? {
            switch self {
            case .github: return "github.com"
            case .gitlab: return "gitlab.com"
            case .gitea: return nil
            }
        }
    }

    var provider: Provider = .github
    /// Empty = the provider's public host (github.com, gitlab.com). Required for Gitea.
    var host: String = ""
    /// "owner/name"; GitLab also "group/subgroup/name".
    var repository: String = ""
    var branch: String = "main"
    var path: String = "brewlog/backup.json"

    var effectiveHost: String? {
        let trimmed = host.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.isEmpty ? provider.defaultHost : trimmed
    }

    // MARK: Validation

    enum Problem: Equatable {
        case host, repository, branch, path
        var message: String {
            switch self {
            case .host: return "Enter the server, e.g. git.example.com."
            case .repository: return "Enter the repository as owner/name."
            case .branch: return "Enter a branch name, e.g. main."
            case .path: return "Enter a file path ending in .json, e.g. brewlog/backup.json."
            }
        }
    }

    var problem: Problem? {
        guard let host = effectiveHost, Self.isHost(host) else { return .host }
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let maxParts = provider == .gitlab ? 20 : 2
        guard parts.count >= 2, parts.count <= maxParts, parts.allSatisfy({ Self.isName($0) }) else { return .repository }
        guard !branch.isEmpty, branch.count <= 100, !branch.contains(".."), !branch.hasPrefix("/"), !branch.hasSuffix("/"),
              branch.allSatisfy({ $0.isLetter || $0.isNumber || "-_./".contains($0) }), branch.allSatisfy(\.isASCII)
        else { return .branch }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.lowercased().hasSuffix(".json"), path.count <= 200, segments.allSatisfy({ Self.isName($0) })
        else { return .path }
        return nil
    }

    var isValid: Bool { problem == nil }

    /// A host name or IP with an optional port, no scheme or path.
    private static func isHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, !host.hasPrefix("."), !host.hasPrefix("-") else { return false }
        let parts = host.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let name = parts.first, !name.isEmpty,
              name.allSatisfy({ ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") && $0.isASCII }) else { return false }
        if parts.count == 2 { return Int(parts[1]).map { (1...65_535).contains($0) } ?? false }
        return true
    }

    /// One path segment: letters, digits, "-", "_", "." but not "." or "..".
    private static func isName<S: StringProtocol>(_ part: S) -> Bool {
        !part.isEmpty && part.count <= 100 && part != "." && part != ".."
            && part.allSatisfy { ($0.isLetter || $0.isNumber || "-_.".contains($0)) && $0.isASCII }
    }

    // MARK: Requests

    private var apiBase: URL? {
        guard isValid, let host = effectiveHost else { return nil }
        switch provider {
        case .github: return URL(string: host == "github.com" ? "https://api.github.com" : "https://\(host)/api/v3")
        case .gitlab: return URL(string: "https://\(host)/api/v4")
        case .gitea: return URL(string: "https://\(host)/api/v1")
        }
    }

    private static let segmentAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-_.")
        return set
    }()

    private func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: Self.segmentAllowed) ?? text
    }

    /// Path segments encoded one by one (GitHub, Gitea), or as a whole with "/" → %2F (GitLab).
    private var encodedPath: String {
        provider == .gitlab ? encoded(path) : path.split(separator: "/").map { encoded(String($0)) }.joined(separator: "/")
    }

    private var fileURL: URL? {
        guard let base = apiBase else { return nil }
        let text: String
        switch provider {
        case .github, .gitea: text = "\(base.absoluteString)/repos/\(repository)/contents/\(encodedPath)"
        case .gitlab: text = "\(base.absoluteString)/projects/\(encoded(repository))/repository/files/\(encodedPath)"
        }
        return URL(string: text)
    }

    private func withRef(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "ref", value: branch)]
        return components?.url
    }

    private func authorize(_ request: inout URLRequest, token: String) {
        switch provider {
        case .github:
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        case .gitlab: request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        case .gitea: request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("BrewLog", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30
    }

    /// File info with the blob sha (the file's id in Git), 404 when the file doesn't exist yet.
    func metadataRequest(token: String) -> URLRequest? {
        guard let url = fileURL.flatMap(withRef) else { return nil }
        var request = URLRequest(url: url)
        authorize(&request, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// The file itself.
    func rawRequest(token: String) -> URLRequest? {
        guard let base = fileURL else { return nil }
        let url: URL?
        switch provider {
        case .github: url = withRef(base)
        case .gitlab: url = withRef(base.appendingPathComponent("raw"))
        case .gitea:
            url = apiBase.flatMap { URL(string: "\($0.absoluteString)/repos/\(repository)/raw/\(encodedPath)") }.flatMap(withRef)
        }
        guard let url else { return nil }
        var request = URLRequest(url: url)
        authorize(&request, token: token)
        request.setValue(provider == .github ? "application/vnd.github.raw+json" : "*/*", forHTTPHeaderField: "Accept")
        return request
    }

    /// Creates or updates the file as a new commit. `sha` is the current blob (nil = create; GitLab only needs to
    /// know whether the file exists).
    func writeRequest(content: Data, sha: String?, message: String, token: String) -> URLRequest? {
        guard let url = fileURL else { return nil }
        var request = URLRequest(url: url)
        authorize(&request, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: String] = ["content": content.base64EncodedString(), "branch": branch]
        switch provider {
        case .github:
            request.httpMethod = "PUT"
            body["message"] = message
            if let sha { body["sha"] = sha }
        case .gitea:
            request.httpMethod = sha == nil ? "POST" : "PUT"
            body["message"] = message
            if let sha { body["sha"] = sha }
        case .gitlab:
            request.httpMethod = sha == nil ? "POST" : "PUT"
            body["commit_message"] = message
            body["encoding"] = "base64"
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// The blob sha from a metadata response (GitHub/Gitea `sha`, GitLab `blob_id`).
    static func blobSHA(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let value = (object["sha"] ?? object["blob_id"]) as? String
        guard let value, value.count <= 128, value.allSatisfy(\.isHexDigit) else { return nil }
        return value
    }

    /// The server's error message, if it sent one.
    static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let message = (object["message"] ?? object["error"]) as? String
        return message.map { String($0.prefix(200)) }
    }
}

/// Change detection for the backup (stable across launches, unlike `Hasher`).
enum ContentHash {
    static func fnv1a(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return String(hash, radix: 16)
    }
}
