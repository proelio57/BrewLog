import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BrewLog

/// Git backup requests for GitHub, GitLab and Gitea. No network, so these also run on Linux.
final class GitRemoteTests: XCTestCase {
    private func body(_ request: URLRequest?) throws -> [String: String] {
        let data = try XCTUnwrap(request?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    func testGitHubRequests() throws {
        let remote = GitRemote(provider: .github, repository: "me/coffee", branch: "main", path: "brewlog/backup.json")
        XCTAssertNil(remote.problem)
        let meta = try XCTUnwrap(remote.metadataRequest(token: "t0k"))
        XCTAssertEqual(meta.url?.absoluteString, "https://api.github.com/repos/me/coffee/contents/brewlog/backup.json?ref=main")
        XCTAssertEqual(meta.value(forHTTPHeaderField: "Authorization"), "Bearer t0k")
        XCTAssertEqual(remote.rawRequest(token: "t")?.value(forHTTPHeaderField: "Accept"), "application/vnd.github.raw+json")

        let write = remote.writeRequest(content: Data("{}".utf8), sha: "abc123", message: "BrewLog backup", token: "t")
        XCTAssertEqual(write?.httpMethod, "PUT")
        XCTAssertEqual(try body(write), ["content": "e30=", "branch": "main", "message": "BrewLog backup", "sha": "abc123"])
        XCTAssertNil(try body(remote.writeRequest(content: Data(), sha: nil, message: "m", token: "t"))["sha"])

        let enterprise = GitRemote(provider: .github, host: "git.corp.example", repository: "me/coffee")
        XCTAssertEqual(enterprise.metadataRequest(token: "t")?.url?.host, "git.corp.example")
        XCTAssertTrue(enterprise.metadataRequest(token: "t")?.url?.path.hasPrefix("/api/v3/") == true)
    }

    func testGitLabRequests() throws {
        let remote = GitRemote(provider: .gitlab, repository: "group/sub/coffee", branch: "main", path: "brewlog/backup.json")
        XCTAssertNil(remote.problem)
        XCTAssertEqual(remote.metadataRequest(token: "t")?.url?.absoluteString,
                       "https://gitlab.com/api/v4/projects/group%2Fsub%2Fcoffee/repository/files/brewlog%2Fbackup.json?ref=main")
        XCTAssertEqual(remote.metadataRequest(token: "t")?.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "t")
        XCTAssertEqual(remote.rawRequest(token: "t")?.url?.absoluteString,
                       "https://gitlab.com/api/v4/projects/group%2Fsub%2Fcoffee/repository/files/brewlog%2Fbackup.json/raw?ref=main")
        XCTAssertEqual(remote.writeRequest(content: Data(), sha: nil, message: "m", token: "t")?.httpMethod, "POST")
        let update = remote.writeRequest(content: Data("x".utf8), sha: "0f0f", message: "m", token: "t")
        XCTAssertEqual(update?.httpMethod, "PUT")
        XCTAssertEqual(try body(update), ["content": "eA==", "branch": "main", "commit_message": "m", "encoding": "base64"])
    }

    func testGiteaRequests() throws {
        XCTAssertEqual(GitRemote(provider: .gitea, repository: "me/coffee").problem, .host, "Gitea needs a server")
        let remote = GitRemote(provider: .gitea, host: "git.home.lan:3000", repository: "me/coffee", path: "backup.json")
        XCTAssertNil(remote.problem)
        XCTAssertEqual(remote.metadataRequest(token: "t")?.url?.absoluteString,
                       "https://git.home.lan:3000/api/v1/repos/me/coffee/contents/backup.json?ref=main")
        XCTAssertEqual(remote.rawRequest(token: "t")?.url?.absoluteString,
                       "https://git.home.lan:3000/api/v1/repos/me/coffee/raw/backup.json?ref=main")
        XCTAssertEqual(remote.metadataRequest(token: "t")?.value(forHTTPHeaderField: "Authorization"), "token t")
        XCTAssertEqual(remote.writeRequest(content: Data(), sha: nil, message: "m", token: "t")?.httpMethod, "POST")
        XCTAssertEqual(remote.writeRequest(content: Data(), sha: "ab", message: "m", token: "t")?.httpMethod, "PUT")
    }

    func testRejectsUnsafeSettings() {
        func problem(_ change: (inout GitRemote) -> Void) -> GitRemote.Problem? {
            var remote = GitRemote(provider: .github, repository: "me/coffee")
            change(&remote)
            return remote.problem
        }
        XCTAssertEqual(problem { $0.repository = "me" }, .repository)
        XCTAssertEqual(problem { $0.repository = "me/../x" }, .repository)
        XCTAssertEqual(problem { $0.repository = "a/b/c" }, .repository, "GitHub has no subgroups")
        XCTAssertEqual(problem { $0.host = "https://evil.example/x" }, .host)
        XCTAssertEqual(problem { $0.host = "example.com:99999" }, .host)
        XCTAssertEqual(problem { $0.branch = "" }, .branch)
        XCTAssertEqual(problem { $0.branch = "a..b" }, .branch)
        XCTAssertEqual(problem { $0.path = "../backup.json" }, .path)
        XCTAssertEqual(problem { $0.path = "backup.txt" }, .path)
        XCTAssertEqual(problem { $0.path = "a b.json" }, .path)
        XCTAssertNil(problem { $0.branch = "feature/brewlog-1" })
        XCTAssertNil(GitRemote(provider: .gitea, repository: "me/coffee").metadataRequest(token: "t"))
    }

    func testParsesResponses() {
        XCTAssertEqual(GitRemote.blobSHA(from: Data(#"{"sha": "3a0f9c", "size": 10}"#.utf8)), "3a0f9c")
        XCTAssertEqual(GitRemote.blobSHA(from: Data(#"{"blob_id": "beef01", "last_commit_id": "x"}"#.utf8)), "beef01")
        XCTAssertNil(GitRemote.blobSHA(from: Data(#"{"sha": "not hex!"}"#.utf8)))
        XCTAssertNil(GitRemote.blobSHA(from: Data("[]".utf8)))
        XCTAssertEqual(GitRemote.errorMessage(from: Data(#"{"message": "Bad credentials"}"#.utf8)), "Bad credentials")
        XCTAssertEqual(ContentHash.fnv1a(Data("a".utf8)), "af63dc4c8601ec8c")
        XCTAssertNotEqual(ContentHash.fnv1a(Data("a".utf8)), ContentHash.fnv1a(Data("b".utf8)))
    }

    func testPrettyBackupIsStable() throws {
        var backup = BrewLogBackup()
        backup.beans = [.init(id: "b1", name: "Gesha")]
        let first = try backup.encoded(exportedAt: Date(timeIntervalSince1970: 0), pretty: true)
        let second = try backup.encoded(exportedAt: Date(timeIntervalSince1970: 0), pretty: true)
        XCTAssertEqual(first, second)
        XCTAssertTrue(String(decoding: first, as: UTF8.self).contains("\n"))
        XCTAssertEqual(try BrewLogBackup.decode(first).beans.first?.name, "Gesha")
    }
}
