# Cross-Platform Parity & AI Maintenance Guide (for Claude, Gemini & Developers)

> **Audience:** Claude, Gemini, coding agents, and human contributors working on BrewLog.  
> **Mission:** Ensure complete feature parity, architectural symmetry, and high-quality maintenance across **iOS (Swift/SwiftUI)**, **Android (Kotlin/Jetpack Compose)**, and **Web (TypeScript/React)**.

---

## 1. Core Philosophy & Non-Negotiable Invariants

Before writing or modifying any code in this repository, Claude and Gemini must respect these core invariants:

1. **Privacy & Security First:**
   - **Zero Telemetry / Zero Ads:** No analytics SDKs, trackers, or third-party monitoring servers.
   - **Zero Unnecessary Permissions:** On Android, Bluetooth permissions must use `android:usesPermissionFlags="neverForLocation"`. Network access is permitted **only** for reading the read-only public recipe feed, querying GitHub releases for self-updating APKs, and the user's own espresso machine (GaggiMate) in the local network.
2. **Offline-First & Local Sovereignty:**
   - All user data (brews, beans, gear, recipes) is stored locally on the user's device (SwiftData on iOS, atomic JSON on Android, IndexedDB on Web; settings in `UserDefaults` / `SharedPreferences` / `localStorage`).
3. **Format Interchangeability:**
   - A backup JSON exported from iOS **must** import flawlessly into Android and Web, and vice versa. The format is specified in `docs/data-formats.md` ("BrewLog backup").
   - Any model field added to one platform must have a safe default on the other platforms so older backups never crash newer app versions.
4. **Mandatory Pre-Compilation Testing:**
   - Always write and run unit tests and linters **before** compiling binaries or finalizing tasks.
5. **Incident Documentation:**
   - Whenever an unexpected compilation, parsing, or toolchain failure occurs, document the incident in `notes.md` (Symptoms, Root Cause, Resolution) and add a regression test.

---

## 2. Cross-Platform Architecture & File Mapping

Use this reference table to find the corresponding implementation files across platforms
(paths relative to `BrewLog/`, `android/app/src/main/java/com/brewlog/app/` and `web/src/`):

| Architectural Role | iOS (Swift / SwiftUI) | Android (Kotlin / Jetpack Compose) | Web (TypeScript / React) |
| :--- | :--- | :--- | :--- |
| **Domain Models** | `Models/Models.swift`, `Recipes/Recipe.swift` | `domain/Models.kt`, `domain/Recipe.kt` | `domain/models.ts`, `domain/recipe.ts` |
| **Validation / Limits** | `Recipes/RecipeValidation.swift` | `domain/Validation.kt` | `domain/validation.ts` |
| **Data Storage** | SwiftData (`@Model` classes in `Models/Models.swift`, container in `App/BrewLogApp.swift`) | `data/Repositories.kt` | `data/repository.ts`, `data/db.ts` |
| **Backup & Importer** | `Import/DataImporter.swift`, `Import/BrewLogBackup.swift`, `Import/BeanconquerorBackup.swift`, `Import/RecipeFile.swift`, `Import/ZipArchive.swift` | `data/DataImporter.kt`, `domain/BeanconquerorBackup.kt`, `domain/RecipeFile.kt` | `import/importer.ts`, `import/beanconqueror.ts`, `import/recipeFile.ts`, `import/zip.ts` |
| **Recipe Feed (Online)** | `Recipes/RecipeFeed.swift` | `data/RecipeFeed.kt` | `data/recipeFeed.ts` |
| **Built-in Recipes & Gear Presets** | `Recipes/RecipeLibrary.swift` + `Shared/recipes.json` | `domain/Library.kt` + `Shared/recipes.json` | `domain/library.ts` + `Shared/recipes.json` |
| **Brew Setup State** | `BrewSetup` in `App/BrewLogApp.swift`, `Brewing/GrindMemory.swift` | `data/BrewSetupState.kt` | `data/setup.ts` |
| **Brewing Engine** | `Brewing/BrewSession.swift` | `brewing/BrewSession.kt` | `brewing/brewSession.ts` |
| **Live Timer / Heads-Up** | `Brewing/BrewLiveActivity.swift`, `ActivityShared/`, `BrewLogWidgets/` (Live Activity & Dynamic Island) | `brewing/BrewNotificationManager.kt` | – |
| **Bluetooth Scale (BLE)** | `Scale/ScaleManager.swift`, `Scale/BookooProtocol.swift` | `scale/ScaleManager.kt`, `scale/BookooProtocol.kt` | `scale/scaleManager.ts`, `scale/bookoo.ts` (Web Bluetooth) |
| **Pressure Sensor (BOOKOO Espresso Monitor)** | `Scale/PressureMonitor.swift`, `Scale/BookooMonitorProtocol.swift` | `scale/PressureManager.kt`, `scale/BookooPressureProtocol.kt` | `scale/pressure.ts` |
| **Espresso Machine (GaggiMate)** | `Machine/MachineManager.swift`, `Machine/MachineStatus.swift` | – (branch `wip/android-espresso-parity`) | `machine/machineManager.ts`, `machine/gaggimate.ts` |
| **Audio & Haptics** | `Audio/SoundPlayer.swift` | `audio/SoundPlayer.kt` | `audio/sound.ts` |
| **Brew Analysis** | `Analysis/BrewAnalyzer.swift`, `Analysis/EspressoAnalyzer.swift`, `Analysis/BrewAnalysis+Brew.swift` (grind recommender) | `analysis/BrewAnalyzer.kt`, `analysis/GrindRecommender.kt` | `analysis/analyzer.ts`, `analysis/espresso.ts`, `analysis/recommender.ts` |
| **App Entry / Root** | `App/BrewLogApp.swift`, `Views/RootView.swift` | `AppContainer.kt` (activity + container), `ui/AppRoot.kt` | `main.tsx`, `app.ts`, `Shell.tsx` |
| **Journal & History UI** | `Views/History/` (`HistoryListView`, `BrewDetailView`, `BrewEditorView`) | `ui/screens/JournalScreen.kt`, `BrewDetailScreen.kt`, `BrewEditorScreen.kt` | `screens/Journal.tsx`, `BrewDetail.tsx`, `BrewEditor.tsx` |
| **Brew Setup & Live Brew** | `Views/Brew/BrewSetupView.swift`, `BrewSessionView.swift`, `MachineCard.swift`, `QuickWeighView.swift` | `ui/screens/BrewSetupScreen.kt`, `LiveBrewScreen.kt`, `QuickWeighScreen.kt` | `screens/BrewSetup.tsx`, `LiveBrew.tsx`, `Machine.tsx`, `QuickWeigh.tsx` |
| **Recipe Library UI** | `Views/Recipes/RecipeViews.swift` | `ui/screens/RecipeScreens.kt` | `screens/Recipes.tsx` |
| **Bean Cellar UI** | `Views/Beans/BeanViews.swift` | `ui/screens/BeanScreens.kt` | `screens/Beans.tsx` |
| **Gear, Grinders & Settings UI** | `Views/Gear/GearViews.swift` | `ui/screens/GearScreens.kt` | `screens/Gear.tsx` |
| **Onboarding** | `Views/Onboarding/OnboardingView.swift` | `ui/screens/OnboardingScreen.kt` | `screens/Onboarding.tsx` |
| **In-App Updater** | SideStore / AltStore source (branch `sidestore`) | `data/AppUpdater.kt` + GitHub Releases | Service worker (`main.tsx`), reload = latest |

---

## 3. Current Feature Parity Status Matrix

| Feature | iOS | Android | Web | Notes for AI Agents |
| :--- | :---: | :---: | :---: | :--- |
| **Preset Recipes** | Yes | Yes | Yes | Sourced from `Shared/recipes.json`, updated by the online recipe list. |
| **Online Recipe List** | Yes | Yes | Yes | Same merge rule and cache (`docs/data-formats.md`). |
| **Custom Recipe Builder** | Yes | Yes | Yes | Step editing, recipe files import/export. |
| **Bean Inventory** | Yes | Yes | Yes | Bag weight, remaining grams, roast date freshness, archiving. |
| **Equipment & Grinder Scale** | Yes | Yes | Yes | Clicks/numbers/dial/microns, step and adjustment size, presets. |
| **Grind Remembered per Grinder** | Yes | Yes | No | Switching grinders restores that grinder's setting, else history, else a starting value (`defaultGrind`). |
| **Live Brew Flow Tracking** | Yes | Yes | Yes | Weight curve, flow rate, step timing, pings. |
| **BOOKOO Scale** | Yes | Yes | Yes | Web: Web Bluetooth (Chromium browsers, not iOS Safari). |
| **Live Activity / Timer** | Yes | Yes | No | iOS: ActivityKit / Dynamic Island. Android: ongoing notification. |
| **Brew Analysis & Grind Suggestions** | Yes | Yes | Yes | Pour-over analysis and history-based grind recommendation. |
| **Edit a Saved Brew** | Yes | Yes | Yes | |
| **Espresso Mode** (recipes, shot screen, espresso analysis) | Yes | Partial | Yes | Android reads espresso recipes; shot screen and analysis are on branch `wip/android-espresso-parity`. |
| **BOOKOO Espresso Monitor** (pressure) | Yes | Yes | Yes | |
| **GaggiMate** | Yes | No | Partial | Web only when the app is opened over http (browsers block `ws://` from https pages). |
| **Backup Export** (wrapped format with curves) | Yes | Partial | Yes | Android exports only the bare `data` object, without weight/machine curves. |
| **Backup Import** (merge by id) | Yes | Partial | Yes | Android reads only the bare `data` object, not the wrapped format from iOS/web. |
| **Beanconqueror Import** | Yes | Yes | Yes | `.zip` and `.json`, de-duplicated by `externalId`. |
| **In-App Self Updater** | Via SideStore | Yes | Reload | Android checks GitHub releases and downloads the APK. |
| **Play Store Bundle (AAB)** | N/A | Yes | N/A | Documented in `docs/play-store.md`, buildable via `./scripts/build-apk.sh --release`. |

---

## 4. How to Restore Parity When a Feature Changes on One Platform

If a new feature is implemented on **iOS** (e.g., in Swift) and needs to be ported to **Android** (or vice versa):

### Step 1: Inspect the Source Diff
Run git diff or examine the commits:
```bash
git log -n 5 --stat
git diff HEAD~1 BrewLog/
```
Identify:
1. Did any domain models change? (New fields, altered enum values, changed defaults).
2. Did repository storage logic change? (New update methods, migrations).
3. Did the data exchange formats change? (Backup JSON schema, Beanconqueror parsing).
4. What UI views and user flows were added or modified?

### Step 2: Update Domain Models with Lenient Defaults
**Critical Rule:** Kotlin `@Serializable` and Swift `Codable` handle missing JSON fields differently.
- In Swift, `decodeIfPresent` or custom initializers can assign default values.
- In Kotlin, **every optional field MUST have an explicit default value in the data class constructor**:
  ```kotlin
  // Good:
  val notes: String = "",
  val targetTime: Double? = null,
  val taste: TasteProfile = TasteProfile()
  ```
  Failure to supply defaults causes `kotlinx.serialization.MissingFieldException` when importing JSON files generated by other platforms.

### Step 3: Implement Business Logic & Repository Methods
Port repository methods symmetrically:
- Swift uses `@Published` / `ObservableObject` or Swift Observation.
- Android uses Kotlin Coroutines `StateFlow<AppData>` with atomic update functions:
  ```kotlin
  repo.update { current ->
      current.copy(...)
  }
  ```
- Ensure any ID generation uses UUID strings (`newId()`).

### Step 4: Write Unit Tests BEFORE Compiling (Mandatory Rule)
Before writing UI code or invoking Gradle/Xcode, write comprehensive unit tests:
1. Test serialization round-trip: Model -> JSON -> Model.
2. Test cross-platform payload compatibility (decode samples generated from the other platform).
3. Test deduplication logic (re-importing the same payload must not create duplicate brews/beans).
4. Run tests:
   ```bash
   JAVA_HOME=/home/proelio/.local/share/jdk-17 ./android/gradlew -p android testDebugUnitTest
   ```

### Step 5: Port UI Screens to Jetpack Compose / SwiftUI
- **Layout Parity:** Match navigation hierarchy (Tab / Bottom Navigation: Journal, Beans, Gear, Recipes, Settings).
- **Theme Parity:** Use the project's curated warm coffee palette:
  - Deep Espresso / Dark surfaces (`#12100E`, `#1A1614`).
  - Warm Caramel / Amber accents (`#E68A3C`, `#D47A2C`).
  - Clean typographic hierarchy with clear contrast ratios.
- **Audio & Haptic parity:** Trigger cues on step transitions.

### Step 6: Verify Linting and Compilation
Run the full Android quality pipeline:
```bash
JAVA_HOME=/home/proelio/.local/share/jdk-17 ./android/gradlew -p android lintDebug
JAVA_HOME=/home/proelio/.local/share/jdk-17 ./scripts/build-apk.sh
```

---

## 5. How to Update Both Platforms Simultaneously ("Double-Barreled Protocol")

When adding a brand-new feature to BrewLog across both platforms at once:

```
                  Simultaneous Multi-Platform Protocol
                  
       1. Define Specification (docs/data-formats.md)
                         |
       +-----------------+-----------------+
       |                                   |
2a. iOS Swift Model                 2b. Android Kotlin Model
       |                                   |
3a. iOS Tests & Repo                3b. Android Tests & Repo
       |                                   |
4a. iOS SwiftUI Screen              4b. Android Compose Screen
       |                                   |
       +-----------------+-----------------+
                         |
          5. Cross-Import Verification Test
                         |
          6. Commit & Verify Lint/CI Pipelines
```

### Detailed Step-by-Step Procedure:

1. **Document the Schema Change First:**
   - Update `docs/data-formats.md` with the new JSON keys, types, and constraints.
2. **Synchronize Model Definitions:**
   - Add the fields to `BrewLog/Models/Models.swift` with `var property: Type? = default`.
   - Add the fields to `android/.../domain/Models.kt` with `val property: Type = default`.
   - Add the fields to `web/src/domain/models.ts` with `property?: Type` and parse them in `web/src/domain/validation.ts`.
3. **Keep `Shared/recipes.json` as the Single Source of Truth:**
   - If adding a new preset recipe, edit `Shared/recipes.json` once. Both iOS and Android reference this file directly.
4. **Implement Platform-Specific Services:**
   - On iOS: Leverage native iOS frameworks (e.g. ActivityKit, CoreBluetooth, AVFoundation).
   - On Android: Leverage Android Jetpack equivalents (e.g. NotificationCompat, BluetoothLeScanner, ToneGenerator / SoundPool).
5. **Cross-Test Import/Export:**
   - Export an AppData backup from Android in unit test -> pass to Swift unit test -> verify all items match.
   - Verify that importing an older backup without the new fields still succeeds with defaults.

---

## 6. Self-Healing & Incident Logging Protocol

If Claude or Gemini encounters any unexpected error:

1. **Do not silently ignore or hack around the error.**
2. **Open `notes.md`:**
   Add a new entry with the current date:
   - **Symptoms:** The exact error message and stack trace.
   - **Root Cause:** Explanation of why it occurred (e.g., toolchain mismatch, missing JDK binary, Kotlin serialization missing default).
   - **Resolution:** What concrete changes were made to fix it permanently.
3. **Add a Regression Test:**
   Write a unit test targeting the root cause to ensure the build fails if the regression is ever reintroduced.

---

## 7. AI Agent Command Reference Cheat-Sheet

### Android (Linux Environment)
```bash
# 1. Environment variables
export JAVA_HOME=/home/proelio/.local/share/jdk-17
export ANDROID_HOME=/home/proelio/Android/Sdk

# 2. Run unit tests
./android/gradlew -p android testDebugUnitTest

# 3. Run Android linter
./android/gradlew -p android lintDebug

# 4. Build debug APK
./scripts/build-apk.sh

# 5. Build release APK & Play Store AAB
./scripts/build-apk.sh --release
```

### Web
```bash
# 1. Run web unit tests
npm --prefix web test

# 2. Typecheck and build web bundle
npm --prefix web run build
```

### iOS (macOS Environment)
```bash
# 1. Regenerate Xcode project if project.yml changed
xcodegen generate

# 2. Run iOS unit tests
xcodebuild test -project BrewLog.xcodeproj -scheme BrewLog -destination 'platform=iOS Simulator,name=iPhone 16'
```
