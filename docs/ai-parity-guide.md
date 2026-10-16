# Cross-Platform Parity & AI Maintenance Guide (for Claude, Gemini & Developers)

> **Audience:** Claude, Gemini, coding agents, and human contributors working on BrewLog.  
> **Mission:** Ensure complete feature parity, architectural symmetry, and high-quality maintenance across **iOS (Swift/SwiftUI)**, **Android (Kotlin/Jetpack Compose)**, and **Web (TypeScript/React)**.

---

## 1. Core Philosophy & Non-Negotiable Invariants

Before writing or modifying any code in this repository, Claude and Gemini must respect these core invariants:

1. **Privacy & Security First:**
   - **Zero Telemetry / Zero Ads:** No analytics SDKs, trackers, or third-party monitoring servers.
   - **Zero Unnecessary Permissions:** On Android, Bluetooth permissions must use `android:usesPermissionFlags="neverForLocation"`. Network access is permitted **only** for reading the read-only public recipe feed and querying GitHub releases for self-updating APKs.
2. **Offline-First & Local Sovereignty:**
   - All user data (brews, beans, gear, recipes) is stored locally on the user's device (`UserDefaults`/JSON on iOS, atomic JSON on Android, IndexedDB on Web).
3. **Format Interchangeability:**
   - A backup JSON exported from iOS **must** import flawlessly into Android and Web, and vice versa.
   - Any model field added to one platform must have a safe default on the other platforms so older backups never crash newer app versions.
4. **Mandatory Pre-Compilation Testing:**
   - Always write and run unit tests and linters **before** compiling binaries or finalizing tasks.
5. **Incident Documentation:**
   - Whenever an unexpected compilation, parsing, or toolchain failure occurs, document the incident in `notes.md` (Symptoms, Root Cause, Resolution) and add a regression test.

---

## 2. Cross-Platform Architecture & File Mapping

Use this reference table to find the corresponding implementation files across platforms:

| Architectural Role | iOS (Swift / SwiftUI) | Android (Kotlin / Jetpack Compose) | Web (TypeScript / React) |
| :--- | :--- | :--- | :--- |
| **Domain Models** | `BrewLog/Models/Models.swift`<br>`BrewLog/Recipes/Recipe.swift` | `android/app/src/main/java/com/brewlog/app/domain/Models.kt`<br>`.../domain/Recipe.kt` | `web/src/types/domain.ts` |
| **Data Storage / Repo** | `BrewLog/Models/BrewRepository.swift` | `android/app/src/main/java/com/brewlog/app/data/BrewRepository.kt` | `web/src/services/BrewRepository.ts` |
| **Backup & Importer** | `BrewLog/Import/DataImporter.swift`<br>`BrewLog/Import/BeanconquerorBackup.swift` | `android/app/src/main/java/com/brewlog/app/data/DataImporter.kt`<br>`.../domain/BeanconquerorBackup.kt` | `web/src/services/dataImporter.ts` |
| **Recipe Feed (Online)**| `BrewLog/Recipes/RecipeFeed.swift` | `android/app/src/main/java/com/brewlog/app/data/RecipeFeed.kt` | `web/src/services/recipeFeed.ts` |
| **Brewing Engine** | `BrewLog/Brewing/BrewEngine.swift` | `android/app/src/main/java/com/brewlog/app/brewing/BrewEngine.kt` | `web/src/services/brewEngine.ts` |
| **Live Timer / Heads-Up**| `ActivityShared/` (ActivityKit Live Activity & Dynamic Island) | `android/app/src/main/java/com/brewlog/app/brewing/BrewNotificationManager.kt` | Web Notifications API |
| **Bluetooth Scale (BLE)**| `BrewLog/Scale/ScaleManager.swift` | `android/app/src/main/java/com/brewlog/app/scale/ScaleManager.kt` | `web/src/services/webBluetoothScale.ts` |
| **Audio & Metronome** | `BrewLog/Audio/AudioCuePlayer.swift` | `android/app/src/main/java/com/brewlog/app/audio/AudioCuePlayer.kt` | Web Audio API / Synthetic Cues |
| **Extraction Analytics** | `BrewLog/Analysis/TastingAnalysis.swift` | `android/app/src/main/java/com/brewlog/app/analysis/TastingAnalysis.kt` | `web/src/services/analysis.ts` |
| **App Entry / Root** | `BrewLog/App/BrewLogApp.swift`<br>`BrewLog/Views/RootView.swift` | `android/app/src/main/java/com/brewlog/app/MainActivity.kt`<br>`.../ui/AppRoot.kt` | `web/src/App.tsx` |
| **Journal & History UI** | `BrewLog/Views/History/HistoryView.swift` | `.../ui/screens/JournalScreen.kt` | `web/src/components/JournalView.tsx` |
| **Live Brew Screen** | `BrewLog/Views/Brew/LiveBrewView.kt` | `.../ui/screens/LiveBrewScreen.kt` | `web/src/components/LiveBrewView.tsx` |
| **Recipe Library UI** | `BrewLog/Views/Recipes/RecipesView.swift` | `.../ui/screens/RecipeScreens.kt` | `web/src/components/RecipeList.tsx` |
| **Bean Cellar UI** | `BrewLog/Views/Beans/BeansView.swift` | `.../ui/screens/BeanScreens.kt` | `web/src/components/BeanCellar.tsx` |
| **Gear & Grinders UI** | `BrewLog/Views/Gear/GearView.swift` | `.../ui/screens/GearScreens.kt` | `web/src/components/GearView.tsx` |
| **In-App Updater** | SideStore / AltStore JSON feed | `.../data/AppUpdater.kt` + GitHub Releases | PWA Service Worker cache |
| **Shared Recipe Seed** | `Shared/recipes.json` | `Shared/recipes.json` (linked/bundled) | `Shared/recipes.json` |

---

## 3. Current Feature Parity Status Matrix

| Feature | iOS | Android | Web | Notes for AI Agents |
| :--- | :---: | :---: | :---: | :--- |
| **Preset Recipes** | Yes | Yes | Yes | Sourced from `Shared/recipes.json`. Updated via remote feed if available. |
| **Custom Recipe Builder** | Yes | Yes | Yes | Full JSON import/export and step editing. |
| **Bean Inventory** | Yes | Yes | Yes | Bag weight tracking, remaining grams, roast date freshness, archiving. |
| **Equipment & Grinder Dial**| Yes | Yes | Yes | Micro-step clicks, calibrated numeric ranges, brewer methods. |
| **Live Brew Flow Tracking**| Yes | Yes | Yes | Real-time flow rate curve ($g/s$), target waterline, phase timing. |
| **Bookoo BLE Scale** | Yes | Yes | Yes | Auto-tare, auto-start timer on first drop, battery & weight streaming. |
| **Live Activity / Timer** | Yes | Yes | Partial | iOS uses ActivityKit / Dynamic Island. Android uses ongoing lock screen `BrewNotificationManager`. |
| **Full AppData Backup Export**| Yes | Yes | Yes | Exports complete state to pretty-printed JSON (`exportBackup`). |
| **Full AppData Restore** | Yes | Yes | Yes | Automatic detection of full backups vs recipe files vs Beanconqueror. |
| **Beanconqueror Import** | Yes | Yes | Yes | Supports both raw `.json` and `.zip` archives with automatic deduplication. |
| **In-App Self Updater** | Via SideStore | Yes | PWA | Android checks GitHub releases and downloads APK directly. |
| **Play Store Bundle (AAB)**| N/A | Yes | N/A | Documented in `docs/play-store.md`, buildable via `./scripts/build-apk.sh --release`. |

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
   - Add the fields to `web/src/types/domain.ts` with `property?: Type`.
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
