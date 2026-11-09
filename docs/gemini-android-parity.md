# Android parity: port the iOS espresso and machine features (for Gemini)

> **Audience:** Gemini (or any coding agent) working on the Android app in `android/`.
> **Goal:** Android gets every feature iOS gained since Android was paused, with the same behaviour, values and
> data formats. iOS (`BrewLog/`) is the reference implementation: read the named Swift files, port them to Kotlin /
> Jetpack Compose, keep names and numbers identical.
>
> Read first: [`docs/ai-parity-guide.md`](ai-parity-guide.md) (rules, file mapping, privacy invariants) and
> [`docs/data-formats.md`](data-formats.md) (backup, recipe, GaggiMate, Decent, La Marzocco formats).
> La Marzocco wire format and test vectors: [`docs/la-marzocco-protocol.md`](la-marzocco-protocol.md).

## 0. Ground rules

- **Privacy (non-negotiable):** no analytics, no new permissions beyond what a feature needs. Bluetooth permissions
  keep `android:usesPermissionFlags="neverForLocation"`. Network only for: recipe feed, update check, the user's own
  GaggiMate in the local network, and the opt-in features (Git backup, Ask Claude, **La Marzocco account**). Secrets
  (La Marzocco login, key) only in `sync/SecretStore.kt` (Android Keystore), never in `SharedPreferences`, backups or
  Git sync.
- **Same values as iOS.** Every number, threshold, key name and user-facing text below is copied from iOS. Don't
  "improve" them; if one looks wrong, fix it on both platforms in the same change.
- **Backups stay interchangeable.** A backup from iOS must import on Android and vice versa. New fields get safe
  defaults; unknown keys are ignored.
- **Tests first.** Pure logic (protocols, parsers, monitors, statistics) gets JVM unit tests under
  `android/app/src/test/java/com/brewlog/app/`, mirroring the iOS tests named per feature. Port the iOS test cases
  1:1 (same inputs, same expected values).
- **Commits:** one feature per commit, Conventional Commits with the `android` scope, e.g.
  `feat(android): Filter | Espresso switch on the Brew tab`. The release notes are generated from the subject line
  only (`scripts/release-notes.sh`), so write it for users, in English, no trailing period.
- **After each feature:** update the row in the parity matrix (`docs/ai-parity-guide.md` §3, Android column) and the
  file mapping table (§2).
- **Checks before every commit** (see guide §7):
  ```bash
  ./android/gradlew -p android testDebugUnitTest
  ./android/gradlew -p android lintDebug
  ./scripts/build-apk.sh
  ```

## 1. What Android already has

Recipes and feed, beans (photos, label scan), gear and grinder scales, grind converter and memory, live brew with
BOOKOO / Timemore, weigh the beans, voice prompts, valve countdown, TDS, water recipes, brew analysis, espresso
recipes + shot screen + espresso analysis, BOOKOO Espresso Monitor, GaggiMate (status, control, send recipe as
profile), backups, Beanconqueror import, Git backup, Ask Claude, self updater, partial widgets.

Relevant Android files today: `machine/MachineManager.kt`, `machine/GaggiMate.kt`, `ui/screens/MachineViews.kt`,
`brewing/BrewSession.kt`, `scale/PressureManager.kt`, `data/BrewSetupState.kt`, `data/DataImporter.kt`,
`ui/screens/BrewSetupScreen.kt`, `ui/screens/LiveBrewScreen.kt`, `ui/screens/GearScreens.kt`,
`ui/screens/OnboardingScreen.kt`, `ui/screens/JournalScreen.kt`.

## 2. Work list (in this order)

Each item: what it does → iOS reference → Android target → tests. Items build on each other; finish one (tests, lint,
APK build, parity guide) before starting the next.

### 2.1 Machine model: generic status, capabilities

- Rename `GaggiMateStatus` → `MachineStatus` (it is the generic live state for every machine).
- `MachineKind`: `NONE, GAGGIMATE, DECENT, LA_MARZOCCO, DEMO` (raw values `none, gaggimate, decent, laMarzocco, demo`,
  titles "None", "GaggiMate", "Decent DE1", "La Marzocco", "Demo machine").
- `MachineCapabilities` set: `PROFILES, TEMPERATURE_NUDGE, MACHINE_SCALE, START_STOP, POWER`.
  GaggiMate + demo: profiles, temperatureNudge, machineScale, startStop. Decent: startStop. La Marzocco: power,
  temperatureNudge. None: nothing.
- `canControl = START_STOP in capabilities && connected` (a machine without it gets "Stop now" instead of an auto stop).
- `readsPressure = kind != NONE && kind != LA_MARZOCCO && status.hasPressure != false`: when true, the BOOKOO pressure
  monitor is **not offered** (hidden in settings, machine card, device strip) and its readings are ignored during a
  shot; the machine's pressure is used.
- `MachineKind.suggested(brewerName)`: name contains "gaggimate" → GAGGIMATE, "decent" → DECENT, "marzocco" →
  LA_MARZOCCO, else null (case-insensitive).
- iOS: `Machine/MachineManager.swift`, `Machine/MachineStatus.swift`. Tests: `EspressoTests.testMachineKindSuggestedFromBrewerName`.

### 2.2 Espresso tab on the Brew screen

- A two-option capsule switch **Filter | Espresso** in the top bar of the Brew tab (also used as **Journal | Stats**).
  Both segments equally wide (as wide as the wider label); the thumb slides (tap or drag; a tap must not jump the thumb
  to the finger first, drag only after > 6 dp); the screen behind changes ~0.26 s after the thumb started, and a newer
  tap cancels a pending change. The switch itself must not be recreated when the screen below changes (otherwise the
  thumb resets). iOS: `CapsuleSwitch` in `Views/Components/Components.swift`, `Views/Brew/BrewSetupView.swift`.
- Mode remembered under `brewMode` (`"filter"` default, `"espresso"`).
- Two independent setups: pour-over keeps the existing `setup.*` keys, espresso uses the same names with prefix
  `espresso.` (recipe, dose, temperature, bean, brewer, grinder, grind). Espresso lists only espresso machines as
  brewers, Filter only the other brewers. iOS: `BrewSetup` + `SetupScope` in `App/BrewLogApp.swift`.
- Espresso screen: device strip (Scale · machine · Pressure tiles, tapping opens their setup; the pressure tile shows
  the machine's pressure when `readsPressure`), recipe card, dose/yield/ratio/temperature card (with a connected
  machine its target temperature, pressure and profile win: "from <machine name>"), machine card, bean, gear & grind,
  before you brew. iOS: `Views/Espresso/DeviceStrip.swift`, `EspressoSetupView.swift`, `Views/Brew/MachineCard.swift`.
- Live shot numbers: time and weight big, then ratio, flow, pressure (+ peak), temperature, first drops.
  iOS: `Views/Espresso/ShotReadouts.swift`.

### 2.3 Auto stop at the target yield (ShotMonitor)

- Stop when `weight + max(flow, 0) × stopLag ≥ yield` (fires once). `stopLag` default 1.0 s, range 0.5–2.5, step 0.1.
- Settled (finish without a machine): ≥ 4 readings within the last 1.5 s, all within ±0.3 g, weight ≥ 90 % of yield.
- With a machine that reports the pump live (GaggiMate, DE1): the pump stopping finishes 3 s later. With La Marzocco
  (cloud, seconds late) the scale/pressure sensor may also start the timer and the settled cup also finishes.
- Machine controllable → `stopShot()`; otherwise a "Stop now — target yield reached" banner + cue.
- Settings: `autoStopShot` (default true), `shotStopLag` (default 1.0).
- iOS: `Brewing/ShotMonitor.swift`, `Brewing/BrewSession.swift` (`checkShot`, `machineStartsShot`). Tests:
  `ShotMonitorTests` (port all cases, incl. `testStopsOnceAndIgnoresNegativeFlow`, `testNoReadingsNoDecision`,
  `testNoYieldNoStop`).

### 2.4 Optional rinse step

Phase `rinsing` before weighing when *Rinse the paper* (`rinsePaper`, default on) is checked; pour-over only. Card
with "Rinsed" / skip. iOS: `BrewSession.swift` (`.rinsing`), `BrewSessionView.swift`.

### 2.5 Brew statistics (Journal | Stats)

Pour-over / espresso, 30 / 90 days / all; brews per week, rating trend, brewing numbers (times, ratios, extraction /
first drops, peak pressure, channeling), beans and recipes ranking. iOS: `Analysis/BrewStats.swift`,
`BrewStats+Brew.swift`, `Views/Stats/StatsView.swift`, `StatsCharts.swift`. Tests: `BrewStatsTests` (port all).
Charts: Compose Canvas or Vico; keep the same buckets and trend rule.

### 2.6 GaggiMate profiles

- **Import as recipes** from a file (Import detects a GaggiMate profile JSON: one profile, a list, or
  `{profiles:[…]}`) and from the machine (`req:profiles:list`; Settings → Espresso machine → "Import profiles as
  recipes").
- Mapping (exactly as `data-formats.md` → GaggiMate): id `gaggimate-<profile id>` (or a slug of the label), label
  without the "BrewLog · " prefix, dose (default 18), yield = last `volumetric` target, else last `ratio` × dose, else
  1:2 — **to 0.1 g, never rounded to whole grams**; pre-infusion phases → pre-infusion step; time = pre-infusion + 25 s
  when a weight/ratio target ends the shot, else the sum of durations (15–120 s); pressure = highest brew-phase
  pressure (default 9); pump pressure/flow `-1` = "hold" (tip says "hold pressure" / "hold flow", never counts as 0);
  every phase as a tip "Phase n: Name · 8 s · 3 bar · to 36 g". Utility profiles are skipped.
- **Profile picker:** espresso screen → "Profile ›" lists the machine's profiles (selected first, favorites starred,
  check mark from `selected`, selection by `id`). Tapping one sends `req:profiles:select` and brews with it: a
  BrewLog-sent profile selects its BrewLog recipe again (via the remembered `machine.profile.<recipeId>` → profile id),
  any other is imported **once** (picking it again keeps the user's edits). The sheet stays open and says "The machine
  isn't connected." when the connection drops.
- iOS: `Machine/GaggiMateProfileImport.swift`, `Views/Espresso/MachineProfilesSheet.swift`,
  `MachineManager.swift` (`refreshProfiles`, `selectProfile`, `recipeID(forProfile:)`). Tests: the GaggiMate cases in
  `ImportTests` (`testGaggiMateProfileBecomesEspressoRecipe`, `…ListSkipsUtilityAndDefaults`,
  `testSummariesUseSelectedFlag`, `testSummariesOrderAndSkip`, `testRatioTargetSetsYield`, `testHoldPressureIsIgnored`,
  `testYieldIsNotRounded`, `testFlowHoldIsLabelledFlow`).

### 2.7 Decent DE1 (Bluetooth)

- Protocol (from `data-formats.md` → Decent DE1): service `0000A000-…`, `A002` RequestedState (write), `A00D`
  ShotSample (notify, 19 bytes, big-endian, scalings in the doc), `A00E` StateInfo (read + notify). A shot runs while
  state 4 with substate 4 or 5; flush/hot water/steam/clean/descale are never shots; substates ≥ 200 and state 11 are
  errors and end a shot. Commands: 0 sleep, 2 idle (also stop), 4 espresso (start), 5 steam, 6 hot water.
- Scan without a service filter, accept devices advertising `A000` **or** named `DE1…`; remember the device; on
  disconnect end a running shot once and reconnect; Bluetooth switched off counts as a disconnect; retry a failed
  connect after 5 s; a start not followed by the espresso state within 2 s → "Start the shot on the machine."
  (group-head controller).
- iOS: `Machine/DecentProtocol.swift` (pure), `Machine/DecentConnection.swift`, `Views/Gear/DecentConnectSheet.swift`.
  Android: `machine/DecentProtocol.kt` (pure), `machine/DecentConnection.kt` (BluetoothLeScanner/BluetoothGatt, same
  permission set as the scale). Tests: `DecentProtocolTests` (port all, incl. the 19-byte vector).

### 2.8 La Marzocco (cloud, opt-in)

- Read `docs/la-marzocco-protocol.md` completely. Installation key (P-256 via `java.security`/Keystore-free
  `KeyPairGenerator("EC")` with `secp256r1`; store the PKCS8 private key + secret + id in `SecretStore`), La Marzocco's
  proof algorithm, signed headers, `/auth/init` once, sign-in / refresh tokens, `/things`, dashboard, STOMP WebSocket
  (OkHttp), commands `CoffeeMachineChangeMode` and `CoffeeMachineSettingCoffeeBoilerTargetTemperature`.
- Behaviour to copy from iOS: nothing is sent before sign-in; a generation counter drops answers that arrive after
  sign-out or a machine switch; the socket has no short timeouts (REST: 10 s / 20 s); garbled frames are ignored and
  don't count as online; a 401 / STOMP ERROR clears the token; reconnect with 5 s, 10 s, 20 s … max 5 min, give up
  after 6 tries with a notice; no new key is created unless the user signs in; "No internet connection." for network
  errors; failed command results are reported; "Reload machines" in the account sheet; ±1 °C taps add up.
- Shots: "Brewing" status = shot; no start/stop through the cloud ("Stop now" banner); no pressure → BOOKOO stays
  available.
- iOS: `Machine/LaMarzoccoAuth.swift`, `LaMarzoccoProtocol.swift`, `LaMarzoccoCloud.swift`,
  `Views/Gear/LaMarzoccoAccountSheet.swift`. Tests: `LaMarzoccoTests` (port all; the proof/secret vectors must match
  exactly, and verify an ECDSA signature with the public key).

### 2.9 Gear and setup assistant

- Gear tab and "Add from presets": espresso machines (brewer with method espresso) in their own section
  **"Espresso machines"**, apart from pour-over brewers. iOS: `GearGroup` in `Views/Gear/GearViews.swift`.
- Setup assistant: brewer tiles split into "Pour-over" / "Espresso machines". New step **"Connect your espresso
  machine"** after the brewer step, only when an espresso machine was picked: tiles GaggiMate / Decent DE1 /
  La Marzocco / Demo machine / Not connected, preselected via `MachineKind.suggested` ("Yours" badge), then the
  GaggiMate address, DE1 pairing or La Marzocco sign-in with live status. The filter step is skipped when only
  espresso machines were picked; progress dots show only relevant steps. The first espresso machine becomes the
  espresso setup's brewer, the first pour-over brewer the filter setup's. iOS: `Views/Onboarding/OnboardingView.swift`.

### 2.10 Widgets (lower priority)

Bring the Glance widgets to the iOS set ("Next brew", "Coffee stats", "Beans left"), computed from
`WidgetSnapshot` like iOS. iOS: `BrewLogWidgets/HomeWidgets.swift`, `ActivityShared/WidgetSnapshot.swift`.

## 3. Definition of done

- Every item above implemented, its tests ported and green, lint clean, APK builds.
- `docs/ai-parity-guide.md`: Android column "Yes" for each item, file mapping rows filled, "paused" notes removed.
- A backup exported on Android with an espresso shot (machine samples) imports on iOS with the same curve, and back.
- Manual run list on a phone: Filter | Espresso switch; demo machine shot with auto stop; GaggiMate profile picker
  (demo profiles); DE1 pairing screen lists nothing without a DE1 and doesn't crash; La Marzocco sign-in with a wrong
  password shows "Wrong La Marzocco login."; setup assistant with "La Marzocco Linea Micra" preselects La Marzocco.

## Pressure view, landscape chart, bigger flow (iOS 2026-11-06)

Port to the shared Compose UI (Android + web). iOS reference: `BrewLog/Brewing/PressureFocus.swift`, `BrewLog/Views/Espresso/PressureFocusReadouts.swift`, `BrewLog/Views/Components/MachineChart.swift` (`emphasis`), `BrewLog/Views/Brew/LandscapeChartView.swift`.

- **Setting "Pressure view"** (`pressure.focus`): Automatic (default) / Always / Off.
  - Automatic: active while the BOOKOO pressure sensor is the pressure source.
  - Always: active whenever the shot has pressure (machine or sensor).
  - Off: never.
  - The decision is fixed when the shot starts, so a sensor dropping out mid-shot doesn't change the layout.
- **Zones** with target = `recipe.pressure`, tolerance ±0.5 bar (boundaries count as on target):
  - below → blue;
  - on target → green;
  - above → red;
  - no target → accent colour.
- **Focus layout with the machine's own pressure** (GaggiMate, DE1; Pressure view "Always"): no giant number. Under a compact TIME row, WEIGHT and PRESSURE sit side by side as two cards, 48 sp each; the pressure card is tinted in the zone colour with "target 9.0 · 0.4 low". Charts: the pressure chart with the target band (55 %), then the weight chart (45 %).
- **Focus layout with the pressure sensor:**
  - TIME and WEIGHT compact at 26 sp.
  - The pressure number at 76 sp bold, in the zone colour, on a 10 % zone-colour background.
  - Caption under the number: "target 9.0 bar · 0.4 low" / "· on target" / "· 0.6 high", or "peak 9.3 bar" without a target.
  - Tiles: Flow (teal), Ratio, Temp, First drops.
  - Charts: only the pressure chart, filling the height that is left (the live screen must never run past the screen edges; the weight chart is in the landscape view), with a 3 dp line, a green ±0.5 bar band with a solid target line, y labels every bar and gridlines every 3 bar, and the latest point as a dot in the zone colour.
- **Normal espresso layout:**
  - Flow becomes a 34 sp teal "FLOW" readout with "target a–b g/s" under TIME/WEIGHT.
  - The pressure tile value is in the zone colour.
  - The pressure chart's target line is solid at 60 % opacity.
  - Filter brews: the g/s under the weight is title size and teal.
- **Setting "Landscape chart"** (`chart.landscape`, default on):
  - A button on the live charts and turning the phone to landscape (brewing or finished) open the charts full screen in landscape.
  - The numbers sit in the left column: time, weight, flow, and pressure in the zone colour.
  - Turning the phone back, or the close button, ends it.
  - Rotate first, then show the view without a slide animation (and the reverse on close), so it never appears sideways for a moment.
- **Brew tab Filter | Espresso:** both mode screens stay built and cross-fade (0.25 s, slight horizontal offset) instead of rebuilding after the switch.
  - With the setting off, there's no button and turning the phone does nothing.

## Recipe header, brewer follows recipe, app stops the shot (iOS 2026-11-09)

- **Brew tab:** a compact recipe row at the very top (RECIPE, name, "dose : water · time · °C", method badge, chevron → recipe picker). The full recipe card stays at the bottom.
- **Brewer follows the recipe:** when the selected recipe changes, and its method isn't "Any pour-over", select the first brewer of that method unless the current brewer already has it. ("Brew this" from the Recipes tab already switches Filter/Espresso.)
- **Stop at the yield:** with the scale on the app and a machine the app can start/stop (GaggiMate, DE1), the shot monitor's stop sends the machine's stop without waiting for the status to call the phase a shot. Any active process that isn't a utility (flush/descale) or grind counts as a shot (`isPullingShot`); a GaggiMate profile's phases ("Prefill", "Fill", "Compressing") may report a phase type other than "brew". If the pump still runs 1.5 s later, send stop again; after another 1.5 s show "Stop now". The armed hint says "BrewLog follows the machine and stops the shot at 38 g".
- **After the shot → steam:** setting "After the shot" (`machine.steamAfterShot`: ask (default) / steam / off), shown for GaggiMate, DE1 and demo. When an espresso brew finishes and the machine is connected: "steam" switches the machine to steam mode, "ask" shows a dialog on the rating screen: "Switch to steam?" with Steam / Always after a shot (sets the setting to steam) / Not now. La Marzocco can't switch to steam from the app.
