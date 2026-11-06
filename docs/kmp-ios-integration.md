# Kotlin Multiplatform (KMP) & Compose Multiplatform (CMP) – iOS Integration Guide for Claude

> **Target Audience:** Claude / developers integrating the shared KMP core (`:shared`) into the iOS app (`BrewLog/`).  
> **Status:** Phase 1 (Domain & Business Analysis Logic) and Phase 2 (Compose Theme, Live Brew Chart, Multiplatform Architecture) are implemented in `:shared` and verified against Android (183/183 tests passing).

---

## 1. What was done in `:shared`

The `:shared` module is located at `android/shared` and is part of the Gradle project in `android/`.

### Configured Targets & Plugins:
- Kotlin Multiplatform Plugin: `org.jetbrains.kotlin.multiplatform` (Kotlin 2.4.21)
- AGP 9.5 KMP Library Plugin: `com.android.kotlin.multiplatform.library`
- Compose Multiplatform Plugin: `org.jetbrains.compose` (1.12.2)
- Targets:
  - `androidTarget` (compileSdk 37, minSdk 26, JVM 17)
  - `iosArm64`
  - `iosSimulatorArm64`
- Framework Configuration:
  - Base Name: `Shared`
  - Static Framework: `isStatic = true`

### What is in `:shared` (commonMain):
1. **Domain Models (`com.brewlog.app.domain`)**:
   - `Models.kt`: `Bean`, `Equipment`, `Brew`, `AppData`, `GrinderSpec`, `RoastLevel`, `ProcessMethod`, `TasteFeedback`, `WeightSample`, `MachineSample`, `PressureSample`, `AppSettings`.
   - `Recipe.kt`: `Recipe`, `RecipeStep`, `BrewMethod`, `StepKind`, `ValveState`, `TasteProfile`.
   - `Extraction.kt`: `Extraction`, `Zone`, `Reading`, `Verdict`, `Strength` (TDS, extraction yield, SCA control chart).
   - `WaterChemistry.kt`: `WaterChemistry` (ppm, GH, KH, minerals, Barista Hustle concentrates).
   - `GrindConverter.kt`: `GrindConverter` (shared micron scale, conversion between grinders).
   - `RecipeFilter.kt`: `RecipeFilter` (brewer matching, clearer alternative for flat cups, sections).
   - `StepAnnouncement.kt`: Spoken voice prompts generator ("Pour to 150 grams.").
   - `Validation.kt`: Input sanitization, clamping, non-decreasing pour validation.
   - `Library.kt`: Equipment and recipe presets.
   - `RecipeFile.kt`: JSON encoder/decoder for custom recipes.
   - `Format.kt`: String formatting, mm:ss, noise-free rounding, `expect`/`actual` for:
     - `fmt0`, `fmt1`, `fmtDecimals` (Android uses `Locale.US`, iOS uses `NSString.stringWithFormat`)
     - `newId()` (Android uses `UUID`, iOS uses `NSUUID`)
     - `formatDate()` (Android uses `DateFormat`, iOS uses `NSDateFormatter`)
     - `currentTimeMillis()` (uses `kotlin.time.Clock.System`)
2. **Analysis Algorithms (`com.brewlog.app.analysis`)**:
   - `BrewAnalyzer.kt`: Pure Pour-over curve detection, metrics, findings, and tailored suggestions ("Grind coarser/finer: go from 24 to 22 clicks on your Comandante C40").
   - `EspressoAnalyzer.kt`: Espresso shot analysis, first drops, pressure drop detection, ratio fine-tuning.
   - `GrindRecommender.kt`: History bracketing and starting grind advice.
   - `WeightCleanup.kt`: Despiking, settled final weight, and centered smoothed flows.
3. **Compose Multiplatform UI Components**:
   - `Theme.kt`: Palette (`Accent`, `FlowTeal`, `LightColors`, `DarkColors`, `BrewLogTheme`).
   - `BrewChart.kt`: Canvas-based weight and flow curve chart (`PureBrewChart`), pressure curve, ideal target curve.
4. **iOS Entry Point**:
   - `MainViewController.kt` in `iosMain`:
     ```kotlin
     fun MainViewController(): UIViewController = ComposeUIViewController {
         BrewLogTheme {
             // Shared Compose Root
         }
     }
     ```

---

## 2. Linking the Framework in Xcode (for Claude)

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`).

### Option A: Direct Embed & Sign Script Phase in Xcode (`embedAndSignAppleFrameworkForXcode`)
In `project.yml` or the Xcode target build phases for `BrewLog`:
Add a Run Script phase **before** the "Compile Sources" phase (or "Embed Frameworks"):

```yaml
targets:
  BrewLog:
    preBuildScripts:
      - name: Compile and Embed KMP Shared Framework
        script: |
          cd "$SRCROOT/../android"
          ./gradlew :shared:embedAndSignAppleFrameworkForXcode
        outputFiles:
          - "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/Shared.framework"
```

And in Xcode Build Settings:
```yaml
    settings:
      FRAMEWORK_SEARCH_PATHS:
        - $(inherited)
        - $(SRCROOT)/../android/shared/build/bin/iosSimulatorArm64/debugFramework
        - $(SRCROOT)/../android/shared/build/bin/iosArm64/debugFramework
      OTHER_LDFLAGS:
        - $(inherited)
        - -framework Shared
```

### Option B: Building XCFramework
Run from terminal or script:
```bash
cd android
./gradlew :shared:assembleSharedReleaseXCFramework
```
Or for debug:
```bash
./gradlew :shared:assembleSharedDebugXCFramework
```
This outputs to:
`android/shared/build/XCFrameworks/debug/Shared.xcframework`

---

## 3. Consuming Shared Logic & UI in Swift

### Using Shared Models and Analyzer:
```swift
import Shared

// Domain models
let recipe = Recipe(...)
let input = AnalysisInput(...)
let analysis = BrewAnalyzer.shared.analyze(input: input)

if let suggested = analysis.suggestedGrind {
    print("Suggested grind: \(suggested)")
}
```

### Embedding the Compose Multiplatform UI:
In SwiftUI:
```swift
import SwiftUI
import Shared

struct ComposeAppView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        MainViewControllerKt.MainViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
```

### Accessing Live Activities & Widgets:
The native Swift widgets and Live Activities (`ActivityKit`, `WidgetKit`) can stay in Swift (`BrewLogWidgets/`, `ActivityShared/`). They can consume data converted from the shared KMP models (`Shared.Brew`, `Shared.WidgetSnapshot`, etc.) or share snapshots via App Group storage.
