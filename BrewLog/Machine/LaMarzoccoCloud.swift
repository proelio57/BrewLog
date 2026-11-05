import Foundation
import Observation

/// Talks to La Marzocco's cloud with the user's own La Marzocco account (opt-in, see docs/la-marzocco-protocol.md):
/// signs in, lists the machines, follows the chosen one's dashboard over a STOMP WebSocket and sends power and
/// temperature commands. Login and key material live only in this phone's Keychain.
@Observable
final class LaMarzoccoCloud {
    enum CloudError: LocalizedError {
        case notSignedIn, wrongLogin, policy, unexpected

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to your La Marzocco account first."
            case .wrongLogin: return "Wrong La Marzocco login."
            case .policy: return "Accept La Marzocco's privacy policy in their app, then try again."
            case .unexpected: return "La Marzocco's service didn't answer as expected. They may have changed it."
            }
        }
    }

    private(set) var machines: [LaMarzoccoProtocol.Machine] = []
    private(set) var signedInAs: String?
    private(set) var machine: LaMarzoccoProtocol.Machine?

    /// Signed in and a machine chosen.
    var isReady: Bool { signedInAs != nil && machine != nil }

    /// Every dashboard update.
    @ObservationIgnored var onStatus: ((MachineStatus) -> Void)?
    /// The machine is reachable through the cloud (true) or not (false).
    @ObservationIgnored var onOnline: ((Bool) -> Void)?
    @ObservationIgnored var onNotice: ((String) -> Void)?

    private static let usernameAccount = "lm.username"
    private static let passwordAccount = "lm.password"
    private static let keyAccount = "lm.installation"
    private static let machineKey = "machine.lmMachine"

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var refreshToken: String?
    @ObservationIgnored private var tokenExpiry = Date.distantPast
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var ping: Timer?
    @ObservationIgnored private var retry: DispatchWorkItem?
    /// The dashboard should be followed (connect() called, not disconnected since).
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var status = MachineStatus()
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    init() {
        signedInAs = Keychain.get(Self.usernameAccount)
        if let data = UserDefaults.standard.data(forKey: Self.machineKey) {
            machine = try? JSONDecoder().decode(LaMarzoccoProtocol.Machine.self, from: data)
        }
    }

    // MARK: Account

    /// Signs in (registering this install with La Marzocco the first time) and lists the account's machines.
    /// The login is only stored once it worked.
    func signIn(username: String, password: String) async throws -> [LaMarzoccoProtocol.Machine] {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else { throw CloudError.wrongLogin }
        let key = try await installationKey()
        try await fetchTokens(path: "/auth/signin", body: ["username": user, "password": password], key: key)
        Keychain.set(user, for: Self.usernameAccount)
        Keychain.set(password, for: Self.passwordAccount)
        let list = LaMarzoccoProtocol.machines(try await request("/things", key: key))
        await MainActor.run {
            signedInAs = user
            machines = list
        }
        return list
    }

    /// Uses this machine from now on and starts following it.
    func choose(_ chosen: LaMarzoccoProtocol.Machine) {
        machine = chosen
        UserDefaults.standard.set(try? JSONEncoder().encode(chosen), forKey: Self.machineKey)
        connect()
    }

    /// Forgets login, key and machine. Nothing is sent to La Marzocco afterwards.
    func signOut() {
        disconnect()
        for account in [Self.usernameAccount, Self.passwordAccount, Self.keyAccount] { Keychain.set(nil, for: account) }
        UserDefaults.standard.removeObject(forKey: Self.machineKey)
        accessToken = nil
        refreshToken = nil
        tokenExpiry = .distantPast
        signedInAs = nil
        machine = nil
        machines = []
    }

    // MARK: Following the machine

    func connect() {
        guard isReady else {
            onOnline?(false)
            return
        }
        wanted = true
        guard socket == nil else { return }
        retry?.cancel()
        Task { [weak self] in await self?.open() }
    }

    func disconnect() {
        wanted = false
        retry?.cancel()
        retry = nil
        closeSocket()
        status = MachineStatus()
    }

    // MARK: Commands

    /// Switches the machine on (brewing mode) or to standby.
    func setPower(_ on: Bool) async -> Bool {
        await command("CoffeeMachineChangeMode", ["mode": on ? "BrewingMode" : "StandBy"])
    }

    /// Sets the coffee boiler's target temperature (rounded to 0.1 °C).
    func setTargetTemperature(_ value: Double) async -> Bool {
        let rounded = (min(max(value, 80), 100) * 10).rounded() / 10
        return await command("CoffeeMachineSettingCoffeeBoilerTargetTemperature",
                             ["boilerIndex": 1, "targetTemperature": rounded])
    }

    private func command(_ name: String, _ body: [String: Any]) async -> Bool {
        guard let machine else { return false }
        do {
            _ = try await request("/things/\(Self.pathSafe(machine.id))/command/\(name)", method: "POST", body: body)
            return true
        } catch {
            let message = error.localizedDescription
            await MainActor.run { onNotice?(message) }
            return false
        }
    }

    // MARK: WebSocket

    private func open() async {
        guard wanted, socket == nil, let machine else { return }
        do {
            let key = try await installationKey()
            let token = try await validAccessToken(key: key)
            // The current state first, so the screen is right before the first push arrives.
            if let dashboard = try? await request("/things/\(Self.pathSafe(machine.id))/dashboard", key: key) {
                await MainActor.run { handle(dashboard: dashboard) }
            }
            await MainActor.run { openSocket(key: key, token: token, serial: machine.id) }
        } catch {
            let cloudError = error as? CloudError
            await MainActor.run {
                onNotice?(error.localizedDescription)
                // A wrong login or policy doesn't fix itself by retrying.
                connectionLost(retry: cloudError == nil || cloudError == .unexpected)
            }
        }
    }

    /// Main thread: opens the STOMP socket and sends CONNECT; SUBSCRIBE follows on CONNECTED.
    private func openSocket(key: LaMarzoccoAuth.InstallationKey, token: String, serial: String) {
        guard wanted, socket == nil, let url = URL(string: LaMarzoccoProtocol.socketURL) else { return }
        var urlRequest = URLRequest(url: url)
        for (name, value) in LaMarzoccoAuth.signedHeaders(key) { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let task = session.webSocketTask(with: urlRequest)
        task.maximumMessageSize = 1_000_000
        socket = task
        task.resume()
        receive(on: task, serial: serial)
        send(LaMarzoccoProtocol.stompFrame("CONNECT", headers: [
            ("host", LaMarzoccoProtocol.host), ("accept-version", "1.2,1.1,1.0"), ("heart-beat", "0,0"),
            ("Authorization", "Bearer \(token)"),
        ]), on: task)
        startPing(task)
    }

    private func receive(on task: URLSessionWebSocketTask, serial: String) {
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.socket === task else { return }
                switch result {
                case .failure:
                    self.connectionLost(retry: true)
                case .success(let message):
                    var text: String?
                    switch message {
                    case .string(let string): text = string
                    case .data(let data): text = String(data: data, encoding: .utf8)
                    @unknown default: break
                    }
                    if let text, let frame = LaMarzoccoProtocol.parseStomp(text) {
                        self.handle(frame: frame, serial: serial, on: task)
                    }
                    self.receive(on: task, serial: serial)
                }
            }
        }
    }

    private func handle(frame: (command: String, headers: [String: String], body: String), serial: String,
                        on task: URLSessionWebSocketTask) {
        switch frame.command {
        case "CONNECTED":
            send(LaMarzoccoProtocol.stompFrame("SUBSCRIBE", headers: [
                ("destination", "/ws/sn/\(Self.pathSafe(serial))/dashboard"), ("ack", "auto"),
                ("id", UUID().uuidString.lowercased()), ("content-length", "0"),
            ]), on: task)
        case "MESSAGE":
            handle(dashboard: Data(frame.body.utf8))
        case "ERROR":
            onNotice?(CloudError.unexpected.localizedDescription)
            connectionLost(retry: true)
        default:
            break
        }
    }

    private func handle(dashboard: Data) {
        let result = LaMarzoccoProtocol.apply(dashboard: dashboard, to: &status)
        guard result.connected else {
            onOnline?(false)
            onNotice?("The machine is offline in La Marzocco's app.")
            return
        }
        onOnline?(true)
        onStatus?(status)
    }

    private func send(_ text: String, on task: URLSessionWebSocketTask) {
        task.send(.string(text)) { _ in }
    }

    private func startPing(_ task: URLSessionWebSocketTask) {
        ping?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, self.socket === task else { return }
            task.sendPing { error in
                if error != nil { DispatchQueue.main.async { if self.socket === task { self.connectionLost(retry: true) } } }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ping = timer
    }

    private func closeSocket() {
        ping?.invalidate()
        ping = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    /// The socket closed or failed: the machine counts as unreachable; try again in a few seconds.
    private func connectionLost(retry shouldRetry: Bool) {
        closeSocket()
        status = MachineStatus()
        onOnline?(false)
        guard wanted, shouldRetry else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wanted else { return }
            Task { await self.open() }
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // MARK: HTTP

    /// The stored installation key, or a new one registered with La Marzocco (stored only after that worked).
    private func installationKey() async throws -> LaMarzoccoAuth.InstallationKey {
        if let json = Keychain.get(Self.keyAccount),
           let key = try? JSONDecoder().decode(LaMarzoccoAuth.InstallationKey.self, from: Data(json.utf8)) {
            return key
        }
        let key = LaMarzoccoAuth.makeKey()
        _ = try await send(path: "/auth/init", method: "POST", body: ["pk": key.publicKeyDER.base64EncodedString()],
                           headers: LaMarzoccoAuth.registrationHeaders(key))
        if let data = try? JSONEncoder().encode(key) { Keychain.set(String(decoding: data, as: UTF8.self), for: Self.keyAccount) }
        return key
    }

    private func validAccessToken(key: LaMarzoccoAuth.InstallationKey) async throws -> String {
        if let accessToken, !LaMarzoccoProtocol.needsRefresh(expiresAt: tokenExpiry) { return accessToken }
        guard let user = Keychain.get(Self.usernameAccount), let password = Keychain.get(Self.passwordAccount) else {
            throw CloudError.notSignedIn
        }
        if let refreshToken, accessToken != nil, tokenExpiry > Date() {
            if (try? await fetchTokens(path: "/auth/refreshtoken", body: ["username": user, "refreshToken": refreshToken],
                                       key: key)) != nil, let accessToken {
                return accessToken
            }
        }
        try await fetchTokens(path: "/auth/signin", body: ["username": user, "password": password], key: key)
        guard let accessToken else { throw CloudError.unexpected }
        return accessToken
    }

    private func fetchTokens(path: String, body: [String: Any], key: LaMarzoccoAuth.InstallationKey) async throws {
        let data = try await send(path: path, method: "POST", body: body, headers: LaMarzoccoAuth.signedHeaders(key))
        guard let tokens = LaMarzoccoProtocol.tokens(data) else { throw CloudError.unexpected }
        accessToken = tokens.access
        refreshToken = tokens.refresh
        tokenExpiry = Date().addingTimeInterval(LaMarzoccoProtocol.tokenLifetime)
    }

    /// An authenticated call (fresh token, signed headers).
    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                         key: LaMarzoccoAuth.InstallationKey? = nil) async throws -> Data {
        let resolved: LaMarzoccoAuth.InstallationKey
        if let key { resolved = key } else { resolved = try await installationKey() }
        let key = resolved
        let token = try await validAccessToken(key: key)
        var headers = LaMarzoccoAuth.signedHeaders(key)
        headers["Authorization"] = "Bearer \(token)"
        return try await send(path: path, method: method, body: body, headers: headers)
    }

    private func send(path: String, method: String, body: [String: Any]?, headers: [String: String]) async throws -> Data {
        guard let url = URL(string: LaMarzoccoProtocol.apiBase + path) else { throw CloudError.unexpected }
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CloudError.unexpected
        }
        guard data.count <= 1_000_000, let http = response as? HTTPURLResponse else { throw CloudError.unexpected }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw CloudError.wrongLogin
        case 403:
            let code = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["code"] as? String
            throw code == "USER_MUST_ACCEPT_POLICY" ? CloudError.policy : CloudError.wrongLogin
        default:
            throw CloudError.unexpected
        }
    }

    /// Serial numbers go into URL paths: letters, digits, "-" and "_" only.
    private static func pathSafe(_ value: String) -> String {
        String(value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" })
    }
}
