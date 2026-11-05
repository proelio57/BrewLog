import Foundation
import Observation

/// Talks to La Marzocco's cloud with the user's own La Marzocco account (opt-in, see docs/la-marzocco-protocol.md):
/// signs in, lists the machines, follows the chosen one's dashboard over a STOMP WebSocket and sends power and
/// temperature commands. Login and key material live only in this phone's Keychain.
///
/// Every connection attempt belongs to a generation; `disconnect()` and `signOut()` start a new one, so answers that
/// arrive afterwards (a slow dashboard request, a token, a socket message) are dropped instead of reviving old state.
@Observable
final class LaMarzoccoCloud {
    enum CloudError: LocalizedError, Equatable {
        case notSignedIn, wrongLogin, policy, offline, unexpected

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to your La Marzocco account first."
            case .wrongLogin: return "Wrong La Marzocco login."
            case .policy: return "Accept La Marzocco's privacy policy in their app, then try again."
            case .offline: return "No internet connection."
            case .unexpected: return "La Marzocco's service didn't answer as expected. They may have changed it."
            }
        }

        /// Trying again later can help (as opposed to a wrong login or a policy to accept).
        var isTemporary: Bool { self == .offline || self == .unexpected }
    }

    private(set) var machines: [LaMarzoccoProtocol.Machine] = []
    private(set) var signedInAs: String?
    private(set) var machine: LaMarzoccoProtocol.Machine?

    /// Signed in and a machine chosen.
    var isReady: Bool { signedInAs != nil && machine != nil }

    /// Every dashboard update while the machine is online.
    @ObservationIgnored var onStatus: ((MachineStatus) -> Void)?
    /// The machine is reachable through the cloud (true) or not (false).
    @ObservationIgnored var onOnline: ((Bool) -> Void)?
    @ObservationIgnored var onNotice: ((String) -> Void)?

    private static let usernameAccount = "lm.username"
    private static let passwordAccount = "lm.password"
    private static let keyAccount = "lm.installation"
    private static let machineKey = "machine.lmMachine"
    private static let maxAttempts = 6

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var refreshToken: String?
    @ObservationIgnored private var tokenExpiry = Date.distantPast
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var ping: Timer?
    @ObservationIgnored private var retry: DispatchWorkItem?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var opening = false
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var online = false
    @ObservationIgnored private var haveDashboard = false
    /// Commands sent and waiting for their result in the dashboard (id → what it was, for the message).
    @ObservationIgnored private var pendingCommands: [String: String] = [:]
    /// The dashboard should be followed (connect() called, not disconnected since).
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var status = MachineStatus()
    /// REST calls: short timeouts.
    @ObservationIgnored private let restSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
    /// The dashboard socket stays open for hours and is quiet while the machine idles: no short timeouts here.
    @ObservationIgnored private let socketSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 24 * 60 * 60
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
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
        let key = try await installationKey(create: true)
        try await fetchTokens(path: "/auth/signin", body: ["username": user, "password": password], key: key,
                              generation: generation)
        Keychain.set(user, for: Self.usernameAccount)
        Keychain.set(password, for: Self.passwordAccount)
        await MainActor.run { signedInAs = user }
        let list = LaMarzoccoProtocol.machines(try await request("/things", key: key))
        await MainActor.run { machines = list }
        return list
    }

    /// Lists the account's machines again with the stored login (to choose another one).
    func reloadMachines() async throws -> [LaMarzoccoProtocol.Machine] {
        guard signedInAs != nil else { throw CloudError.notSignedIn }
        let list = LaMarzoccoProtocol.machines(try await request("/things"))
        await MainActor.run { machines = list }
        return list
    }

    /// Remembers the machine to follow. `MachineManager.laMarzoccoChanged()` then reconnects to it.
    func choose(_ chosen: LaMarzoccoProtocol.Machine) {
        machine = chosen
        UserDefaults.standard.set(try? JSONEncoder().encode(chosen), forKey: Self.machineKey)
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
        failures = 0
        guard socket == nil, !opening else { return }
        retry?.cancel()
        openNow()
    }

    func disconnect() {
        wanted = false
        generation += 1
        opening = false
        retry?.cancel()
        retry = nil
        closeSocket()
        status = MachineStatus()
        online = false
        haveDashboard = false
        pendingCommands = [:]
    }

    // MARK: Commands

    /// Switches the machine on (brewing mode) or to standby.
    func setPower(_ on: Bool) async -> Bool {
        await command("CoffeeMachineChangeMode", ["mode": on ? "BrewingMode" : "StandBy"],
                      what: on ? "switch on" : "go to standby")
    }

    /// Sets the coffee boiler's target temperature (rounded to 0.1 °C).
    func setTargetTemperature(_ value: Double) async -> Bool {
        let rounded = (min(max(value, 80), 100) * 10).rounded() / 10
        return await command("CoffeeMachineSettingCoffeeBoilerTargetTemperature",
                             ["boilerIndex": 1, "targetTemperature": rounded], what: "change the temperature")
    }

    private func command(_ name: String, _ body: [String: Any], what: String) async -> Bool {
        guard let machine, wanted else { return false }
        do {
            let answer = try await request("/things/\(Self.pathSafe(machine.id))/command/\(name)", method: "POST", body: body)
            if let id = LaMarzoccoProtocol.commandID(answer) {
                await MainActor.run { pendingCommands[id] = what }
            }
            return true
        } catch {
            let message = error.localizedDescription
            await MainActor.run { onNotice?(message) }
            return false
        }
    }

    // MARK: WebSocket

    private func openNow() {
        guard wanted, socket == nil, !opening else { return }
        opening = true
        let generation = self.generation
        Task { [weak self] in await self?.open(generation: generation) }
    }

    private func open(generation: Int) async {
        guard let machine else { return }
        do {
            guard signedInAs != nil else { throw CloudError.notSignedIn }
            let key = try await installationKey(create: false)
            let token = try await validAccessToken(key: key, generation: generation)
            // The current state first, so the screen is right before the first push arrives.
            if let dashboard = try? await request("/things/\(Self.pathSafe(machine.id))/dashboard", key: key) {
                await MainActor.run { if generation == self.generation { handle(dashboard: dashboard) } }
            }
            await MainActor.run {
                guard generation == self.generation else { return }
                opening = false
                openSocket(key: key, token: token, serial: machine.id)
            }
        } catch {
            let cloudError = error as? CloudError ?? .unexpected
            await MainActor.run {
                guard generation == self.generation else { return }
                opening = false
                onNotice?(cloudError.localizedDescription)
                connectionLost(retry: cloudError.isTemporary)
            }
        }
    }

    /// Main thread: opens the STOMP socket and sends CONNECT; SUBSCRIBE follows on CONNECTED.
    private func openSocket(key: LaMarzoccoAuth.InstallationKey, token: String, serial: String) {
        guard wanted, socket == nil, let url = URL(string: LaMarzoccoProtocol.socketURL) else { return }
        var urlRequest = URLRequest(url: url)
        for (name, value) in LaMarzoccoAuth.signedHeaders(key) { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let task = socketSession.webSocketTask(with: urlRequest)
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
                    if self.socket === task { self.receive(on: task, serial: serial) }
                }
            }
        }
    }

    private func handle(frame: (command: String, headers: [String: String], body: String), serial: String,
                        on task: URLSessionWebSocketTask) {
        switch frame.command {
        case "CONNECTED":
            failures = 0
            send(LaMarzoccoProtocol.stompFrame("SUBSCRIBE", headers: [
                ("destination", "/ws/sn/\(Self.pathSafe(serial))/dashboard"), ("ack", "auto"),
                ("id", UUID().uuidString.lowercased()), ("content-length", "0"),
            ]), on: task)
            // The dashboard request before the socket failed: fetch it now, an idle machine may not push for hours.
            if !haveDashboard { refreshDashboard(serial: serial) }
        case "MESSAGE":
            handle(dashboard: Data(frame.body.utf8))
        case "ERROR":
            // Usually a rejected token: sign in again on the next attempt.
            accessToken = nil
            onNotice?(CloudError.unexpected.localizedDescription)
            connectionLost(retry: true)
        default:
            break
        }
    }

    private func refreshDashboard(serial: String) {
        let generation = self.generation
        Task { [weak self] in
            guard let self, let data = try? await self.request("/things/\(Self.pathSafe(serial))/dashboard") else { return }
            await MainActor.run { if generation == self.generation { self.handle(dashboard: data) } }
        }
    }

    /// Main thread.
    private func handle(dashboard: Data) {
        guard wanted, let result = LaMarzoccoProtocol.apply(dashboard: dashboard, to: &status) else { return }
        haveDashboard = true
        for (id, outcome) in result.commandResults {
            guard let what = pendingCommands.removeValue(forKey: id), outcome != "Success" else { continue }
            onNotice?("The machine didn't \(what) (\(outcome.lowercased())).")
        }
        switch result.connected {
        case false?:
            if online || !haveReportedOffline { onNotice?("The machine is offline in La Marzocco's app.") }
            haveReportedOffline = true
            online = false
            onOnline?(false)
        case true?:
            haveReportedOffline = false
            online = true
            onOnline?(true)
            onStatus?(status)
        case nil:
            // The message doesn't say: only follow it while the machine is known to be online.
            if online { onStatus?(status) }
        }
    }

    @ObservationIgnored private var haveReportedOffline = false

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

    /// The socket closed or failed: the machine counts as unreachable; try again with growing pauses
    /// (5 s, 10 s, 20 s … up to 5 min), and give up after a few attempts until the user reconnects.
    private func connectionLost(retry shouldRetry: Bool) {
        closeSocket()
        status = MachineStatus()
        online = false
        haveDashboard = false
        onOnline?(false)
        guard wanted, shouldRetry else { return }
        failures += 1
        guard failures < Self.maxAttempts else {
            onNotice?("Couldn't reach your machine through La Marzocco. Open the machine settings to try again.")
            return
        }
        let delay = min(5 * pow(2, Double(failures - 1)), 300)
        let work = DispatchWorkItem { [weak self] in self?.openNow() }
        retry?.cancel()
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: HTTP

    /// The stored installation key. Only signing in may make (and register) a new one: a phone that is locked
    /// can't read the Keychain, and that must not replace the registered key.
    private func installationKey(create: Bool) async throws -> LaMarzoccoAuth.InstallationKey {
        if let json = Keychain.get(Self.keyAccount),
           let key = try? JSONDecoder().decode(LaMarzoccoAuth.InstallationKey.self, from: Data(json.utf8)) {
            return key
        }
        guard create else { throw CloudError.offline }  // locked or missing: try again later
        let key = LaMarzoccoAuth.makeKey()
        _ = try await send(path: "/auth/init", method: "POST", body: ["pk": key.publicKeyDER.base64EncodedString()],
                           headers: LaMarzoccoAuth.registrationHeaders(key))
        if let data = try? JSONEncoder().encode(key) { Keychain.set(String(decoding: data, as: UTF8.self), for: Self.keyAccount) }
        return key
    }

    private func validAccessToken(key: LaMarzoccoAuth.InstallationKey, generation: Int? = nil) async throws -> String {
        let generation = generation ?? self.generation
        if let accessToken, !LaMarzoccoProtocol.needsRefresh(expiresAt: tokenExpiry) { return accessToken }
        // Keychain unreadable while the phone is locked: temporary, unlike a sign-out.
        guard let user = Keychain.get(Self.usernameAccount), let password = Keychain.get(Self.passwordAccount) else {
            throw signedInAs == nil ? CloudError.notSignedIn : CloudError.offline
        }
        if let refreshToken, accessToken != nil, tokenExpiry > Date(),
           (try? await fetchTokens(path: "/auth/refreshtoken", body: ["username": user, "refreshToken": refreshToken],
                                   key: key, generation: generation)) != nil,
           let accessToken {
            return accessToken
        }
        try await fetchTokens(path: "/auth/signin", body: ["username": user, "password": password], key: key,
                              generation: generation)
        guard let accessToken else { throw CloudError.unexpected }
        return accessToken
    }

    private func fetchTokens(path: String, body: [String: Any], key: LaMarzoccoAuth.InstallationKey,
                             generation: Int) async throws {
        let data = try await send(path: path, method: "POST", body: body, headers: LaMarzoccoAuth.signedHeaders(key))
        guard let tokens = LaMarzoccoProtocol.tokens(data) else { throw CloudError.unexpected }
        await MainActor.run {
            // Signed out or switched meanwhile: don't bring the tokens back.
            guard generation == self.generation else { return }
            accessToken = tokens.access
            refreshToken = tokens.refresh
            tokenExpiry = Date().addingTimeInterval(LaMarzoccoProtocol.tokenLifetime)
        }
    }

    /// An authenticated call (fresh token, signed headers).
    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                         key: LaMarzoccoAuth.InstallationKey? = nil) async throws -> Data {
        let resolved: LaMarzoccoAuth.InstallationKey
        if let key { resolved = key } else { resolved = try await installationKey(create: false) }
        let token = try await validAccessToken(key: resolved)
        var headers = LaMarzoccoAuth.signedHeaders(resolved)
        headers["Authorization"] = "Bearer \(token)"
        do {
            return try await send(path: path, method: method, body: body, headers: headers)
        } catch CloudError.wrongLogin {
            // The token was rejected (e.g. revoked): sign in again next time.
            await MainActor.run { accessToken = nil }
            throw CloudError.wrongLogin
        }
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
            (data, response) = try await restSession.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw CloudError.offline
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

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed,
    ]

    /// Serial numbers go into URL paths: letters, digits, "-" and "_" only.
    private static func pathSafe(_ value: String) -> String {
        String(value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" })
    }
}
