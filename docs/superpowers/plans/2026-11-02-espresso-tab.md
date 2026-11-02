# Espresso Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Espresso mode in the Brew tab (switch *Filter | Espresso* at the top) with its own remembered setup and a shot screen that starts, measures (weight, flow, ratio, pressure, temperature), stops at the target yield and finishes by itself.

**Architecture:** Shot decisions (stop now, finished, live numbers) live in a pure `ShotMonitor` that `BrewSession` feeds with readings; the views only show its state. Espresso gets a second `BrewSetup` instance with its own UserDefaults keys, injected through a custom environment key. The Brew tab gets a segmented control *Filter | Espresso* at the top; the tab bar stays unchanged.

**Tech Stack:** Swift 5 mode, SwiftUI, SwiftData, iOS 17; XCTest. Pure logic also runs on Linux (`swift:6.1` Docker image).

**Spec:** `docs/superpowers/specs/2026-11-02-espresso-tab-and-stats-design.md` (part A)

## Global Constraints

- iOS only. Android is paused; web later. Parity guide gets rows with Android "No (paused)", Web "No".
- Tab bar unchanged (Brew · Recipes · Journal · Beans · Gear). The Brew tab's mode is a segmented `Picker` *Filter | Espresso* at the top, remembered under `SettingsKey.brewMode` (`"filter"` default, `"espresso"`).
- Pour-over setup keeps the existing `setup.*` keys (no migration); espresso uses the same names with prefix `espresso.` (e.g. `espresso.recipeID`).
- Stop rule: stop when `weight + max(flow, 0) × stopLag ≥ yield`. `stopLag` default 1.0 s, range 0.5–2.5 s, step 0.1.
- Settled rule without a machine: ≥ 4 readings within the last 1.5 s, all within ±0.3 g, and weight ≥ 90 % of the yield.
- Pump stop with a machine: finish 3 s later (existing behaviour, keep).
- Start triggers (existing, keep): machine pump on, pressure ≥ 1 bar, weight ≥ `AppSettings.autoStartThreshold`.
- GaggiMate wins: when connected, temperature = machine `targetTemperature` → measured average (`MachineSample.c`) → recipe; pressure target = machine `targetPressure` → recipe `pressure`. Pull shot never calls `sendProfile`.
- New settings keys: `autoStopShot` (Bool, default true), `shotStopLag` (Double, default 1.0).
- Copy is English, sentence case, no exclamation marks (matches the app).
- Verification: pure logic with `scripts/test-pure-swift.sh` (Task 1); everything with iOS CI: `gh workflow run ios.yml --ref "$(git branch --show-current)"` then `gh run watch "$(gh run list --branch "$(git branch --show-current)" --workflow ios.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status` → exit 0, "Executed N tests, with 0 failures".

## Review Focus

- Yield reached while flow is negative or noisy (cup bumped): no premature stop — `max(flow, 0)` and the stop fires once only (ShotMonitor test `testStopsOnceAndIgnoresNegativeFlow`).
- Scale disconnects mid-shot (no readings): the shot neither stops nor finishes on its own; the user's Stop still works (ShotMonitor test `testNoReadingsNoDecision`).
- Machine connected but not controllable (`canControl == false`): "Stop now" cue and banner instead of `stopShot` (Task 3 step on the cue path; checked in manual run list).
- Recipe without a positive yield (water ≤ 0): auto stop is off for that shot, no division by zero in the live ratio (ShotMonitor test `testNoYieldNoStop`).
- Switching Filter ↔ Espresso: each mode keeps its own recipe, dose, bean and grind (Task 2 test `testScopesDoNotShareKeys`); a brewlog://start link starts the mode that is selected.

---

### Task 1: ShotMonitor (pure shot logic) and the Linux test runner

**Files:**
- Create: `BrewLog/Brewing/ShotMonitor.swift`
- Create: `scripts/test-pure-swift.sh`
- Test: `BrewLogTests/ShotMonitorTests.swift`

**Interfaces:**
- Produces:
  - `struct ShotMonitor` with `init(yield: Double, dose: Double, stopLag: Double, autoStop: Bool)`
  - `mutating func ingest(grams: Double, flow: Double, at t: TimeInterval) -> ShotMonitor.Action` where `enum Action: Equatable { case none, stop, finish }`
  - read-only: `firstDropsTime: TimeInterval?` (first t with grams ≥ 1), `liveRatio: Double?` (grams / dose, nil when dose ≤ 0 or grams < 1), `stopped: Bool`
  - `static func shouldStop(weight: Double, flow: Double, yield: Double, lag: Double) -> Bool`
  - `static func isSettled(_ readings: [(t: TimeInterval, grams: Double)], now: TimeInterval) -> Bool`
  - `static func shotTemperature(recipe: Double, machineTarget: Double?, measuredAverage: Double?) -> Double` (first non-nil, finite, 70–105 °C of target → average → recipe)
  - `static func targetPressure(recipe: Double?, machineTarget: Double?) -> Double?` (machine target in 1–15 bar wins)
  - `scripts/test-pure-swift.sh <test file> <source files…>`: builds a throw-away SwiftPM package (module `BrewLog`, `-swift-version 5`) in a temp dir and runs it in `swift:6.1`; exit status of the tests.

- [ ] **Step 1: Write the failing tests** in `BrewLogTests/ShotMonitorTests.swift` (`@testable import BrewLog`):

```swift
func testStopsAheadOfTheYield() {
    XCTAssertTrue(ShotMonitor.shouldStop(weight: 34.2, flow: 2.0, yield: 36, lag: 1.0))   // 36.2 ≥ 36
    XCTAssertFalse(ShotMonitor.shouldStop(weight: 33.5, flow: 2.0, yield: 36, lag: 1.0))  // 35.5
}
func testStopsOnceAndIgnoresNegativeFlow() {
    var m = ShotMonitor(yield: 36, dose: 18, stopLag: 1.0, autoStop: true)
    XCTAssertEqual(m.ingest(grams: 35.9, flow: -5, at: 20), .none)   // bump: negative flow counts as 0
    XCTAssertEqual(m.ingest(grams: 36.0, flow: 1.5, at: 20.1), .stop)
    XCTAssertEqual(m.ingest(grams: 37.0, flow: 1.5, at: 20.2), .none)  // only once
}
func testFinishesWhenSettledAfterNinetyPercent() {
    var m = ShotMonitor(yield: 36, dose: 18, stopLag: 1.0, autoStop: false)
    var action = ShotMonitor.Action.none
    for i in 0..<8 { action = m.ingest(grams: 33.0 + (i.isMultiple(of: 2) ? 0.1 : 0), flow: 0, at: 30 + Double(i) * 0.2) }
    XCTAssertEqual(action, .finish)   // 33 g ≥ 32.4 (90 %), settled within ±0.3 g
}
func testNotFinishedBelowNinetyPercent() {
    var m = ShotMonitor(yield: 36, dose: 18, stopLag: 1.0, autoStop: false)
    for i in 0..<10 { XCTAssertEqual(m.ingest(grams: 20, flow: 0, at: Double(i) * 0.2), .none) }
}
func testFirstDropsAndLiveRatio() {
    var m = ShotMonitor(yield: 36, dose: 18, stopLag: 1.0, autoStop: true)
    _ = m.ingest(grams: 0.4, flow: 0.2, at: 5)
    _ = m.ingest(grams: 1.2, flow: 0.8, at: 6.5)
    XCTAssertEqual(m.firstDropsTime, 6.5)
    XCTAssertEqual(m.liveRatio ?? 0, 1.2 / 18, accuracy: 0.0001)
}
func testNoYieldNoStop() {
    var m = ShotMonitor(yield: 0, dose: 0, stopLag: 1.0, autoStop: true)
    XCTAssertEqual(m.ingest(grams: 50, flow: 3, at: 10), .none)
    XCTAssertNil(m.liveRatio)
}
func testGaggiMateWins() {
    XCTAssertEqual(ShotMonitor.shotTemperature(recipe: 93, machineTarget: 91, measuredAverage: 90.4), 91)
    XCTAssertEqual(ShotMonitor.shotTemperature(recipe: 93, machineTarget: nil, measuredAverage: 90.4), 90.4)
    XCTAssertEqual(ShotMonitor.shotTemperature(recipe: 93, machineTarget: 0, measuredAverage: nil), 93) // implausible
    XCTAssertEqual(ShotMonitor.targetPressure(recipe: 9, machineTarget: 6), 6)
    XCTAssertEqual(ShotMonitor.targetPressure(recipe: 9, machineTarget: nil), 9)
}
func testNoReadingsNoDecision() {
    XCTAssertFalse(ShotMonitor.isSettled([], now: 10))
    XCTAssertFalse(ShotMonitor.isSettled([(t: 9.9, grams: 30), (t: 10, grams: 30)], now: 10)) // < 4 readings
}
```

- [ ] **Step 2: Write `scripts/test-pure-swift.sh`** (bash, `set -euo pipefail`): copy the given sources to `$tmp/Sources/BrewLog/`, the test file to `$tmp/Tests/BrewLogTests/`, write a `Package.swift` (tools 5.9, target `BrewLog` with `unsafeFlags(["-swift-version","5"])`, test target `BrewLogTests`), run `docker run --rm -v "$tmp":/pkg -w /pkg swift:6.1 swift test`, remove `$tmp` on exit. Run: `bash scripts/test-pure-swift.sh BrewLogTests/ShotMonitorTests.swift BrewLog/Brewing/ShotMonitor.swift` → Expected: FAIL (`cannot find 'ShotMonitor' in scope`).

- [ ] **Step 3: Implement `ShotMonitor`** in `BrewLog/Brewing/ShotMonitor.swift` (Foundation only). Keep the last 1.5 s of readings for `isSettled`; `ingest` returns `.stop` at most once and only when `autoStop && yield > 0`; returns `.finish` once settled at ≥ 0.9 × yield (also after a `.stop`).

- [ ] **Step 4: Run the tests** — same command → Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 5: Commit** — `git add BrewLog/Brewing/ShotMonitor.swift BrewLogTests/ShotMonitorTests.swift scripts/test-pure-swift.sh && git commit -m "feat(ios): ShotMonitor decides when an espresso shot stops and finishes"`

### Task 2: Separate espresso setup and settings

**Files:**
- Modify: `BrewLog/App/BrewLogApp.swift` (`BrewSetup`, app root injecting both setups)
- Modify: `BrewLog/App/Settings.swift`
- Test: `BrewLogTests/BrewSetupScopeTests.swift`

**Interfaces:**
- Produces:
  - `enum SetupScope { case pourOver, espresso; var keyPrefix: String }` — `"setup."` / `"espresso."`
  - `BrewSetup.init(scope: SetupScope = .pourOver, defaults: UserDefaults = .standard)`; all keys become `scope.keyPrefix + name` (pour-over prefix reproduces today's keys exactly).
  - `extension EnvironmentValues { var espressoSetup: BrewSetup }` (custom `EnvironmentKey`, default `BrewSetup(scope: .espresso)`); the app injects one shared instance.
  - Default espresso recipe: first preset with `method == .espresso`; pour-over default: first preset that isn't espresso.
  - `SettingsKey.autoStopShot = "autoStopShot"` (default true), `SettingsKey.shotStopLag = "shotStopLag"` (default 1.0); `AppSettings.autoStopShot: Bool`, `AppSettings.shotStopLag: Double`.

- [ ] **Step 1: Write the failing tests** (suite-named `UserDefaults(suiteName: UUID().uuidString)!`):
  - `testScopesDoNotShareKeys`: espresso setup `select(espressoRecipe)` + `beanID = x`; a new pour-over setup on the same defaults has neither.
  - `testPourOverKeepsTodaysKeys`: defaults set `"setup.recipeID" = "rao-v60"` → `BrewSetup(scope: .pourOver, defaults:)` has `recipe.id == "rao-v60"`.
  - `testDefaultsPerScope`: empty defaults → espresso setup recipe `.method.isEspresso == true`; pour-over setup recipe `.method.isEspresso == false`.
- [ ] **Step 2: Run on CI** (command in Global Constraints) → Expected: FAIL to compile (`extra argument 'scope'`).
- [ ] **Step 3: Implement** the scope, the injected `defaults`, the environment key, both settings with defaults in `AppSettings.registerDefaults` (the existing defaults dictionary).
- [ ] **Step 4: Run on CI** → Expected: all tests pass.
- [ ] **Step 5: Commit** — `feat(ios): espresso remembers its own setup`

### Task 3: Shot session — auto stop, auto finish, live numbers

**Files:**
- Modify: `BrewLog/Brewing/BrewSession.swift`

**Interfaces:**
- Consumes: `ShotMonitor` (Task 1), `AppSettings.autoStopShot`, `AppSettings.shotStopLag` (Task 2).
- Produces on `BrewSession` (observable, read-only): `firstDropsTime: TimeInterval?`, `liveRatio: Double?`, `peakPressure: Double`, `currentPressure: Double?`, `currentTemperature: Double?`, `stopRequested: Bool` (true after a `.stop` without machine control; drives the "Stop now" banner).

- [ ] **Step 1:** Create the `ShotMonitor` in `begin(at:)` when `isEspresso` with `yield: recipe.water`, `dose: dose`, `stopLag: AppSettings.shotStopLag`, `autoStop: AppSettings.autoStopShot`.
- [ ] **Step 2:** In `ingest` (phase `.brewing`, espresso only) call `monitor.ingest(grams:flow:at:)` with `t = date - startDate`; on `.stop`: if `followsMachine && machine.canControl` → `machine.stopShot()`, else `stopRequested = true; fire(.target)`; on `.finish` → `onAutoFinish?()` (skip when `followsMachine`; the pump-stop path finishes those).
- [ ] **Step 3:** Update `peakPressure` / `currentPressure` in `recordPressure`, `currentTemperature` from `machineReading`; expose `firstDropsTime` and `liveRatio` from the monitor. Capture `machine.status.targetTemperature` / `targetPressure` at `begin(at:)` (`machineTargetTemperature`, `machineTargetPressure`, read-only).
- [ ] **Step 3b:** In `BrewSessionView.finish()` for espresso: `brew.waterTemp = ShotMonitor.shotTemperature(recipe: config.waterTemp, machineTarget: session.machineTargetTemperature, measuredAverage: <average of session.machineSamples c>)`; when `ShotMonitor.targetPressure(...)` differs from `recipe.pressure`, save the recipe snapshot with that pressure so `EspressoAnalyzer` judges against the machine.
- [ ] **Step 4:** Build on CI → Expected: success, all tests pass.
- [ ] **Step 5: Commit** — `feat(ios): espresso shots stop at the target yield and finish by themselves`

### Task 4: Shot screen readouts

**Files:**
- Create: `BrewLog/Views/Espresso/ShotReadouts.swift`
- Modify: `BrewLog/Views/Brew/BrewSessionView.swift` (espresso uses `ShotReadouts` instead of the pour-over readouts; "Stop now" banner)

**Interfaces:**
- Consumes: Task 3 properties.
- Produces: `struct ShotReadouts: View { let session: BrewSession }` — grid: Time (`mm:ss`), Weight (`0.0 g`), Ratio (`1:x.x` or `–`), Flow (`0.0 g/s`), Pressure (`0.0 bar`, peak below as `peak 9.1`), Temp (`93.0 °C` or `–`), First drops (`7 s` or `–`).

- [ ] **Step 1:** Implement `ShotReadouts`; pressure tile hidden when `!session.hasPressure`, temperature tile hidden without a machine.
- [ ] **Step 2:** In `BrewSessionView`, espresso phases `.armed`/`.brewing`/`.finished` show `ShotReadouts`; when `session.stopRequested` show an orange banner "Stop now — target yield reached" above the controls.
- [ ] **Step 3:** Build on CI → Expected: success.
- [ ] **Step 4: Commit** — `feat(ios): live shot readouts with ratio, flow, pressure and temperature`

### Task 5: Filter | Espresso switch and the espresso screen

**Files:**
- Create: `BrewLog/Views/Espresso/EspressoSetupView.swift`
- Create: `BrewLog/Views/Espresso/DeviceStrip.swift`
- Modify: `BrewLog/Views/Brew/BrewSetupView.swift` (segmented control at the top; Filter content as today without `machineSection`; Espresso content = `EspressoSetupView`)
- Modify: `BrewLog/Views/Recipes/RecipeViews.swift` (`RecipePickerView(setup: BrewSetup, espresso: Bool)`)
- Modify: `BrewLog/App/Settings.swift` (`SettingsKey.brewMode`)

**Interfaces:**
- Consumes: `\.espressoSetup` (Task 2), `MachineManager.shared`, `PressureMonitor.shared`, `ScaleManager.shared`, existing `MachineCard`, `GrindInputView`, `BrewConfig`, `BrewSessionView`.
- Produces: `enum BrewMode: String { case filter, espresso }`; `struct EspressoSetupView: View`; `struct DeviceStrip: View` (scale · GaggiMate · monitor, each: name, state label, live value `12.3 g` / `8.9 bar` / `93 °C`; tap opens the existing sheets).

- [ ] **Step 1:** `BrewSetupView`: `Picker("Mode", selection: $brewMode)` with `.pickerStyle(.segmented)` pinned at the top (`@AppStorage(SettingsKey.brewMode)`); Filter shows today's content minus `machineSection`; the recipe picker gets `espresso: false`.
- [ ] **Step 2:** `EspressoSetupView`: `DeviceStrip`, recipe card (`RecipePickerView(setup: espressoSetup, espresso: true)`), dose / yield / ratio, temperature (when GaggiMate is connected: its target temperature, target pressure and profile, labelled "from GaggiMate", no stepper; otherwise the recipe's with the stepper), bean, grinder + `GrindInputView`, `MachineCard`, primary button "Pull shot" → `BrewConfig` from the espresso setup with `waterTemp` = machine target when connected. Pull shot never calls `sendProfile`.
- [ ] **Step 3:** brewlog://start starts the selected mode (Filter → today's `startBrew`, Espresso → "Pull shot").
- [ ] **Step 4:** Build on CI → success, all tests pass.
- [ ] **Step 5: Commit** — `feat(ios): Filter | Espresso switch with its own espresso screen`

### Task 6: Settings and docs

**Files:**
- Modify: `BrewLog/Views/Gear/GearViews.swift` (Espresso section: Toggle "Stop at the target yield", Slider "Stop lead x.x s" 0.5–2.5 step 0.1, footer: "BrewLog stops the shot when the weight plus the current flow times this lead reaches the yield, so drips land on target.")
- Modify: `docs/ai-parity-guide.md` (rows "Espresso Tab" and "Auto Stop at Yield": iOS Yes, Android No (paused), Web No; file-map row "Espresso Tab")
- Modify: `README.md` (Espresso bullet)

- [ ] **Step 1:** Implement the settings UI bound to `SettingsKey.autoStopShot` / `SettingsKey.shotStopLag`.
- [ ] **Step 2:** Update the docs.
- [ ] **Step 3:** CI → success. Manual checks on the phone with the demo scale and demo pressure sensor: Pull shot starts, live ratio and pressure move, "Stop now" appears at the yield, the shot finishes by itself and the journal entry has both curves.
- [ ] **Step 4: Commit** — `feat(ios): espresso auto-stop settings`
