# Pressure Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** During an espresso shot with a pressure sensor connected, the screen is about the pressure: a big, colour-coded bar number and a big pressure graph with a clearly visible target line, so the pressure can be dialled in by hand. The flow (g/s) in the normal layout gets bigger and coloured too.

**Architecture:** One pure decision type (`PressureFocus`) answers "show the focus layout?" and "is this pressure low / on target / high?"; it has unit tests. A new view `PressureFocusReadouts` replaces `ShotReadouts` while focus is active, and `BrewSessionView.liveCharts` swaps the chart sizes. A three-way setting (Automatic / Always / Off) lives in `SettingsKey` and is shown next to the pressure sensor row. iOS only: Android and the web get the same behaviour later from the shared Compose UI (entry in the parity doc).

**Tech Stack:** SwiftUI, Swift Charts, XCTest; XcodeGen project (`project.yml`). Swift is only built on the macOS CI (`.github/workflows/ios.yml`); there is no local Swift toolchain, so "run tests" means push and read the `Unit tests` step.

**Spec:** the user's request (2026-11-06), verbatim:
> Aber finds bisschen schwer zu sehen, weil gibt kein horizontal und ist so klein dann und nicht farblich. Also muss erstmal suchen mit den Augen. Beim pressure reading vom grafen, wenn ein pressure monitor verbunden ist, soll der fokus auf dem grafen und druckanzeige als zahl sein, damit man manuell den druck richtig finden kann und es soll klar sein und gut lesbar, das setting kann man auch togglen wenn man will ohne pressure monitor, default bleibt aber so bzw wird da auch g/s größer und auch deutlicher erkennbar gemacht.

Read "kein horizontal" as: no clear horizontal target line in the pressure chart (today a faint dashed rule at 35 % opacity). If it means landscape orientation, that is a separate task, not in this plan.

## Global Constraints

- iOS 17 deployment target; SwiftUI + Swift Charts only, no new dependencies.
- Default behaviour: the focus layout turns on automatically only when the BOOKOO pressure sensor is the pressure source (`PressureMonitor.isReady && !machine.readsPressure`); everything else keeps today's layout, apart from the bigger flow readout.
- Setting key: `SettingsKey.pressureFocus = "pressure.focus"`, raw values `"automatic"` (default), `"always"`, `"off"`.
- Target tolerance: ±0.5 bar around `recipe.pressure`. Colours: below → `.blue`, on target → `.green`, above → `.red`, no target → `Color.accentColor`. Flow colour: `.teal` (same as the flow line in `BrewChart` and `MachineChart`).
- Numbers use `.monospacedDigit()` and `.contentTransition(.numericText())`, like `ShotReadouts.big`.
- UI copy in English, matching existing strings ("Pressure view", "Automatic", "Always", "Off").
- Release notes come from commit subjects: user-facing commits are `feat(ios): …`, one line each, no bodies.

## Review Focus

1. Sensor connected, recipe without `pressure` (nil) → the number shows in the neutral accent colour, there's no target band and no "target" line under the number, and nothing crashes. Test: `testZoneWithoutTarget` (Task 1).
2. Sensor drops out mid-shot (`monitor.isReady` false) in Automatic mode → the layout must not flip back and forth during the shot; it keeps the layout chosen when the shot started. Test: `testFocusIsLatchedForTheShot` (Task 1).
3. Readings above the 12 bar chart range (sensor spike) → the chart clamps to 12 (as today) but the number shows the real value. Covered by Task 3's chart clamp; no extra test, check in the screenshot step.
4. "Always" with no pressure source at all (no sensor, machine without pressure) → no focus layout; there is nothing to focus on. Test: `testAlwaysNeedsAPressureSource` (Task 1).
5. Pressure exactly on the boundary (target ± 0.5) counts as on target. Test: `testZoneBoundariesAreOnTarget` (Task 1).

---

### Task 1: `PressureFocus` decision and zones

**Files:**
- Create: `BrewLog/Brewing/PressureFocus.swift`
- Modify: `BrewLog/App/Settings.swift` (add `SettingsKey.pressureFocus`)
- Test: `BrewLogTests/PressureFocusTests.swift`

**Interfaces:**
- Produces:
  - `enum PressureFocusMode: String, CaseIterable { case automatic, always, off }` with `var title: String` ("Automatic", "Always", "Off").
  - `enum PressureZone: Equatable { case low, onTarget, high, noTarget }`.
  - `enum PressureFocus` with
    - `static let tolerance = 0.5`
    - `static func isActive(mode: PressureFocusMode, sensorIsSource: Bool, hasPressure: Bool) -> Bool`: automatic → `sensorIsSource`; always → `hasPressure`; off → false.
    - `static func zone(pressure: Double?, target: Double?) -> PressureZone`: nil target or nil pressure → `.noTarget`; `|p − t| <= tolerance` → `.onTarget`; else low/high.
- `BrewSession` gets `private(set) var pressureFocus: Bool` (latched; see Task 2).

- [ ] **Step 1: Write the failing tests** in `BrewLogTests/PressureFocusTests.swift`:

```swift
func testAutomaticFollowsTheSensor() {
    XCTAssertTrue(PressureFocus.isActive(mode: .automatic, sensorIsSource: true, hasPressure: true))
    XCTAssertFalse(PressureFocus.isActive(mode: .automatic, sensorIsSource: false, hasPressure: true))
}
func testAlwaysNeedsAPressureSource() {
    XCTAssertTrue(PressureFocus.isActive(mode: .always, sensorIsSource: false, hasPressure: true))
    XCTAssertFalse(PressureFocus.isActive(mode: .always, sensorIsSource: false, hasPressure: false))
}
func testOffNeverFocuses() {
    XCTAssertFalse(PressureFocus.isActive(mode: .off, sensorIsSource: true, hasPressure: true))
}
func testZones() {
    XCTAssertEqual(PressureFocus.zone(pressure: 7.9, target: 9), .low)
    XCTAssertEqual(PressureFocus.zone(pressure: 9.2, target: 9), .onTarget)
    XCTAssertEqual(PressureFocus.zone(pressure: 10.1, target: 9), .high)
}
func testZoneBoundariesAreOnTarget() {
    XCTAssertEqual(PressureFocus.zone(pressure: 8.5, target: 9), .onTarget)
    XCTAssertEqual(PressureFocus.zone(pressure: 9.5, target: 9), .onTarget)
}
func testZoneWithoutTarget() {
    XCTAssertEqual(PressureFocus.zone(pressure: 9, target: nil), .noTarget)
    XCTAssertEqual(PressureFocus.zone(pressure: nil, target: 9), .noTarget)
}
func testUnknownStoredModeFallsBackToAutomatic() {
    XCTAssertEqual(PressureFocusMode(rawValue: "bogus") ?? .automatic, .automatic)
}
```

- [ ] **Step 2: Push and confirm the CI `Unit tests` step fails** with "cannot find 'PressureFocus' in scope".

- [ ] **Step 3: Implement** `PressureFocus.swift` (Foundation only, so the tests stay platform-neutral) and add `static let pressureFocus = "pressure.focus"` to `SettingsKey`.

- [ ] **Step 4: Push; the `Unit tests` step passes.**

- [ ] **Step 5: Commit** `feat(ios): pressure view setting and target zones` *(folded into Task 2's user-facing commit if pushed together; either way one `feat` line in the notes)*.

### Task 2: Latch the focus decision in `BrewSession`

**Files:**
- Modify: `BrewLog/Brewing/BrewSession.swift` (next to `hasPressure`, line ~238; reset with the other shot state, line ~461)
- Test: `BrewLogTests/PressureFocusTests.swift`

**Interfaces:**
- Consumes: `PressureFocus.isActive(mode:sensorIsSource:hasPressure:)`, `PressureFocusMode`.
- Produces: `BrewSession.pressureFocus: Bool`. Computed live until the shot starts (`phase` before `.brewing`), then frozen until the session resets. Reads the mode from `UserDefaults.standard.string(forKey: SettingsKey.pressureFocus)`. `sensorIsSource` is the existing private `usesSensor`.

- [ ] **Step 1: Write the failing test** `testFocusIsLatchedForTheShot`. Build a session the way `ShotMonitorTests` / `EspressoTests` do (demo pressure sensor). Start the shot with the sensor ready, then make the sensor not ready, then assert `session.pressureFocus` is still `true`. After `reset()` / a new session with the sensor off, assert `false`. Reuse the helpers in `EspressoTests.swift`; don't add new fakes.
- [ ] **Step 2: Push; the test fails.**
- [ ] **Step 3: Implement.** Store `latchedFocus: Bool?`; set it when the phase becomes `.brewing`; clear it where `peakPressure = 0` is reset.
- [ ] **Step 4: Push; tests pass.**
- [ ] **Step 5: Commit** together with Task 1: `feat(ios): pressure view for manual pressure control when a pressure sensor is connected`.

### Task 3: Focus layout and a readable pressure chart

**Files:**
- Create: `BrewLog/Views/Espresso/PressureFocusReadouts.swift`
- Modify: `BrewLog/Views/Brew/BrewSessionView.swift:43-47` (choose readouts) and `:72-83` (`liveCharts`)
- Modify: `BrewLog/Views/Components/MachineChart.swift` (target band + emphasis parameter)

**Interfaces:**
- Consumes: `BrewSession.pressureFocus`, `PressureFocus.zone(pressure:target:)`, the existing `livePressure` logic of `ShotReadouts` (move it to a `BrewSession`/view extension `livePressure(machine:monitor:) -> Double?` so both views share it, instead of copying it).
- Produces:
  - `struct PressureFocusReadouts: View { let session: BrewSession }`, with the layout below.
    - **Row 1:** a compact TIME and WEIGHT row at 28 pt rounded semibold.
    - **Centre:** the pressure number at 96 pt rounded bold with `.minimumScaleFactor(0.5)` and the unit "bar" at title size. It is coloured by zone (Global Constraints colours) and has a caption line underneath.
      - Caption with a target: "target 9.0 bar · 0.4 low" / "on target" / "0.6 high".
      - Caption without a target: "peak 9.3 bar".
    - **Bottom:** one row of small tiles: Flow (teal), Ratio, Temp (if the machine is connected) and First drops.
  - `MachineChart(… emphasis: Bool = false)`. With `emphasis`:
    - the pressure line is 3 pt wide;
    - the target shows as a `RectangleMark` band of ±`PressureFocus.tolerance` (green, 0.18 opacity) plus a solid 1.5 pt green `RuleMark`;
    - the y-axis labels every 1 bar and the gridlines every 3 bar;
    - a live `PointMark` at the latest sample is coloured by zone.

    Without `emphasis` the target `RuleMark` still becomes solid, at 0.6 opacity and 1 pt, so it is easier to see than today.
- `liveCharts` when `session.pressureFocus`: `MachineChart(emphasis: true, height: 240)` first, then `BrewChart(height: 90)`. Otherwise the current order and heights stay.

- [ ] **Step 1: Implement `PressureFocusReadouts`** and switch in `BrewSessionView`. The switch: `session.isEspresso && [.armed, .brewing, .finished].contains(session.phase)` → `session.pressureFocus ? PressureFocusReadouts : ShotReadouts`.
- [ ] **Step 2: Implement `MachineChart(emphasis:)`** and the new `liveCharts` order. Accessibility label of the readouts: "Pressure 9.1 bar, on target".
- [ ] **Step 3: Push. CI builds and the existing UI test `DemoBrewFlowUITests` still passes.**
- [ ] **Step 4: Screenshot check.** In the simulator, with the demo sensor (Settings → Pressure sensor → Demo sensor) and the setting Automatic, start an espresso recipe with `pressure: 9`. Take screenshots during the shot in light and dark mode and attach them to the PR. Expected:
  - the number is readable at arm's length (≥ 96 pt);
  - its colour changes as the demo pressure crosses 8.5 and 9.5;
  - the target band is clearly visible.
- [ ] **Step 5: Commit** `feat(ios): big colour-coded pressure readout and target band in the pressure chart`.

### Task 4: Setting in the UI, bigger flow in the normal layout, docs

**Files:**
- Modify: `BrewLog/Views/Gear/GearViews.swift:540-545` (machine section, next to `PressureMonitorRow`)
- Modify: `BrewLog/Views/Espresso/ShotReadouts.swift` (flow readout)
- Modify: `docs/gemini-android-parity.md` (new entry), `README.md` if it lists espresso features

**Interfaces:**
- Consumes: `PressureFocusMode`, `SettingsKey.pressureFocus`.

- [ ] **Step 1: Setting row.** Add `Picker("Pressure view", selection: $mode)` with `@AppStorage(SettingsKey.pressureFocus) private var mode: PressureFocusMode = .automatic`. Show it always, not only when the sensor row shows, because "Always" is meant for machines like GaggiMate that read pressure themselves. Footer sentence: "Automatic: a big pressure number and graph while a pressure sensor is connected, for setting the pressure by hand. Always: also with the machine's own pressure."
- [ ] **Step 2: Bigger, coloured flow** in `ShotReadouts` (the default layout). Take Flow out of the tile grid and give it a third "big" readout under TIME/WEIGHT:
  - 34 pt rounded semibold, `.teal`, label "FLOW";
  - the detail line shows the recipe's target range if set: "target 1.5–2.5 g/s".
  - Keep the tile grid for Ratio, Pressure, Temp and First drops. The pressure tile value is coloured by zone.
- [ ] **Step 3: Push; CI is green**, including `DemoBrewFlowUITests`. If that test looks up the "Flow" tile by text, change the lookup to the new readout's accessibility label "Flow".
- [ ] **Step 4: Parity entry.** Add a section to `docs/gemini-android-parity.md` describing:
  - the three-way setting;
  - the latch rule;
  - the zone colours and tolerance;
  - the layout sizes.

  This lets the shared Compose UI copy the behaviour.
- [ ] **Step 5: Commit** `feat(ios): pressure view setting and a bigger, coloured flow readout` (docs in the same commit, or a separate `docs:` commit).

---

## Self-review notes

- **Spec coverage:**
  - Focus on graph + number with a sensor → Tasks 2 and 3.
  - Clear and readable → 96 pt number, colour and band (Task 3).
  - Toggle without the sensor → "Always" (Tasks 1 and 4).
  - Default stays → Automatic (Task 1).
  - g/s bigger and clearer → Task 4, step 2.
  - "nicht farblich" → zone colours and teal flow.
  - "kein horizontal" → target band and solid target line (Task 3).
- **Types:**
  - `PressureFocusMode`, `PressureZone`, `PressureFocus.isActive(mode:sensorIsSource:hasPressure:)`, `PressureFocus.zone(pressure:target:)` and `BrewSession.pressureFocus` are used with the same names in every task.
  - `MachineChart(emphasis:)` defaults to false, so `BrewDetailView` stays unchanged.
