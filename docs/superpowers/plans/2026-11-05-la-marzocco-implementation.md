# La Marzocco (Cloud) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A La Marzocco home machine (Linea Micra, Mini, Mini R, GS3) shows up in BrewLog through the user's own La Marzocco account: the shot timer follows the machine's "Brewing" state, the boiler state and target temperature are shown, and the machine can be switched on/standby and its brew temperature changed.

**Architecture:** Pure `LaMarzoccoAuth` (installation key, request proof, signed headers) and `LaMarzoccoProtocol` (dashboard JSON → `MachineStatus`, STOMP frames) with tests; a `LaMarzoccoCloud` client (URLSession REST + WebSocket, tokens) feeding `MachineManager` as `MachineKind.laMarzocco`; an account sheet in Settings. Credentials and key material in the Keychain only.

**Tech Stack:** Swift 5 mode, SwiftUI, CryptoKit (P256 ECDSA, SHA256), URLSession WebSocket, iOS 17, XCTest.

**Spec:** Decision 2026-11-05 (user: "mit Cloud"), plan `2026-11-05-la-marzocco.md`; protocol `docs/la-marzocco-protocol.md` (pylamarzocco v2.5.6).

## Global Constraints

- Opt-in: nothing is sent to La Marzocco until the user picks "La Marzocco" as machine **and** signs in. The sign-in sheet says plainly: "BrewLog talks to La Marzocco's servers with your La Marzocco account. Your login stays in this phone's Keychain."
- Keychain only (`Keychain` in `Import/GitSync.swift`, accounts `lm.username`, `lm.password`, `lm.installation`): never in UserDefaults, backups or Git sync. "Sign out" deletes all three and the serial.
- Hosts exactly as in `docs/la-marzocco-protocol.md`; HTTPS/WSS only; responses capped at 1 MB.
- `MachineCapabilities` for `.laMarzocco`: new `.power` and `.temperatureSet` only — no profiles, no machine scale, no start/stop (the API has none), no pressure (`hasPressure = false` → BOOKOO sensor stays available).
- Shot following: `CMMachineStatus.status == "Brewing"` → `processActive`, `processKind = "brew"`; anything else → not brewing. Boiler `targetTemperature` → `targetTemperature`; no live temperature.
- Errors shown as `notice`: 401 "Wrong La Marzocco login.", 403 `USER_MUST_ACCEPT_POLICY` "Accept La Marzocco's privacy policy in their app, then try again.", other/unknown "La Marzocco's service didn't answer as expected. They may have changed it." Never crash or spin forever (10 s timeouts).
- Docs: `docs/data-formats.md` links `docs/la-marzocco-protocol.md`; `docs/ai-parity-guide.md` §1 lists the opt-in La Marzocco connection next to Git backup and Ask Claude; README feature line.

## Review Focus

- Token expiry while the app was in the background: the next call refreshes (or signs in again) instead of failing (`testTokenNeedsRefresh` on the pure token-state helper).
- The machine is offline (`connected: false` in the dashboard): state `.unreachable` with "The machine is offline in La Marzocco's app.", no shot started.
- Sign-out while the WebSocket is open: socket closed, Keychain cleared, status reset, no further requests.
- A dashboard without `CMMachineStatus` or with unknown widget codes: parsed without crash, unknown widgets ignored (`testUnknownWidgetsIgnored`).
- STOMP frame split or with extra headers / `ERROR` frame: handled, `ERROR` shown as notice and the socket reconnects once (`testDecodesStompFrames`).

---

### Task 1: LaMarzoccoAuth (pure)

**Files:** Create `BrewLog/Machine/LaMarzoccoAuth.swift`; Test `BrewLogTests/LaMarzoccoTests.swift`

**Interfaces — Produces:**
```swift
enum LaMarzoccoAuth {
    struct InstallationKey: Codable, Equatable { let installationID: String; let privateKey: Data /* P256 raw */; let secret: Data }
    static func makeKey(installationID: String = UUID().uuidString.lowercased()) -> InstallationKey
    static func secret(installationID: String, publicKeyDER: Data) -> Data
    static func baseString(installationID: String, publicKeyDER: Data) -> String
    static func proof(_ input: String, secret: Data) -> String
    static func signedHeaders(_ key: InstallationKey, nonce: String = UUID().uuidString.lowercased(), now: Date = Date()) -> [String: String]
    static func registrationHeaders(_ key: InstallationKey) -> [String: String]
}
```
- [ ] Step 1: tests with the vectors from `docs/la-marzocco-protocol.md` (`testProofVectors`, `testSecretAndBaseString` using pubDER = bytes 0…90), plus `testSignedHeadersVerify` (signature verifies with the key's public key over `"<id>.<nonce>.<ts>.<proof>"`, header names exact, timestamp in ms).
- [ ] Step 2: CI fails (type missing). Step 3: implement with CryptoKit (`P256.Signing`, `derRepresentation` for key and signature). Step 4: CI green. Step 5: commit `feat(ios): La Marzocco request signing`.

### Task 2: LaMarzoccoProtocol (pure)

**Files:** Create `BrewLog/Machine/LaMarzoccoProtocol.swift`; Test `BrewLogTests/LaMarzoccoTests.swift` (fixture JSON trimmed from pylamarzocco `dashboard_micra.json` into the test file)

**Interfaces — Produces:**
```swift
enum LaMarzoccoProtocol {
    struct Machine: Equatable, Identifiable { let id: String /* serial */; let name: String; let model: String }
    static func machines(_ json: Data) -> [Machine]                       // only type CoffeeMachine
    static func apply(dashboard json: Data, to status: inout MachineStatus) -> (connected: Bool, commandResults: [String: String])
    static func stompFrame(_ command: String, headers: [(String, String)], body: String = "") -> String
    static func parseStomp(_ text: String) -> (command: String, headers: [String: String], body: String)?
    static func tokens(_ json: Data) -> (access: String, refresh: String)?
    static func needsRefresh(expiresAt: Date, now: Date) -> Bool          // < 10 min left
}
```
- [ ] Tests: `testDashboardBrewing` (status Brewing → `isBrewing`, target 94.0), `testDashboardStandby` (mode StandBy → `MachineMode.standby`), `testUnknownWidgetsIgnored`, `testOfflineMachine` (connected false), `testDecodesStompFrames` (CONNECTED, MESSAGE with body, ERROR, missing `\0`), `testMachinesListFiltersGrinders`, `testTokenNeedsRefresh`.
- [ ] Implement, CI green, commit `feat(ios): read La Marzocco's machine dashboard`.

### Task 3: Cloud client, MachineManager, Settings

**Files:** Create `BrewLog/Machine/LaMarzoccoCloud.swift`, `BrewLog/Views/Gear/LaMarzoccoAccountSheet.swift`; Modify `MachineManager.swift` (`MachineKind.laMarzocco` "La Marzocco", capabilities `.power, .temperatureSet`), `MachineCard.swift` (power toggle + temperature stepper for these capabilities instead of the mode picker / nudge), `GearViews.swift` (account row), `App/Settings.swift` (`machineLMSerial`), docs listed in Global Constraints.

**Interfaces — Produces:** `final class LaMarzoccoCloud` with `signIn(username:password:) async throws -> [LaMarzoccoProtocol.Machine]`, `connect(serial:)`, `disconnect()`, `signOut()`, `setPower(_ on: Bool) async -> Bool`, `setTargetTemperature(_ value: Double) async -> Bool`, callbacks `onStatus(MachineStatus)`, `onState(MachineManager.ConnectionState)`, `onNotice(String)`.

- [ ] Client: registers once (`/auth/init`) when the key is new, keeps tokens in memory, refreshes per `needsRefresh`, WebSocket with STOMP CONNECT/SUBSCRIBE, reconnect after 5 s on close, 15 s ping.
- [ ] Manager: `.laMarzocco` routes `setMode(.standby/.brew)` to power, temperature to the setter; shot following through the existing `apply(status:telemetry:)` (telemetry false — no samples).
- [ ] Settings: account sheet (email, password, consent text, Sign in → machine list → pick), Sign out.
- [ ] CI green; manual run list for the user: sign in, machine appears, power on/standby from BrewLog, temperature change shows in La Marzocco's app, a shot on the machine starts and stops BrewLog's timer, airplane mode → "offline" and recovery, sign out clears everything.
- [ ] Commit `feat(ios): La Marzocco machines through your La Marzocco account`.
