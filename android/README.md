# BrewLog for Android

The Android version of BrewLog: native **Kotlin + Jetpack Compose**, with the same features and the same analysis rules as the iOS app. The folder is self-contained, so you can copy just `android/` to any PC and build it there.

- BOOKOO Themis Mini over Bluetooth LE, or the built-in demo scale
- Guided brewing: auto-start on the first pour, a soft ping just before each target, a chime when each step starts, and a countdown ring
- One chart with weight (left axis) and flow in g/s (right axis) against the recipe curve
- Setup assistant, Quick weigh, recipes (incl. your own), beans, gear (CAFEC/Hario filters, grinder scales), journal
- Rule-based taste feedback with concrete grind suggestions ("go from 24 to 22 clicks"), filter- and roast-aware

## Build and install on Windows

### 1. Install Android Studio

Download it from <https://developer.android.com/studio> and run the standard setup. It installs everything else: the JDK, Android SDK, platform tools and the emulator.

### 2. Open the project

1. Copy the `android` folder somewhere with a short path, e.g. `C:\dev\BrewLog\android`. Very long paths can break Windows builds.
2. Android Studio → **Open** → select the `android` folder.
3. Wait for the Gradle sync to finish. The first sync downloads Gradle and the libraries, so it takes a few minutes. If Android Studio asks to install **Android SDK Platform 37**, accept.

### 3. Run it

**In the emulator (no phone needed):**
- Device Manager → create a device (e.g. Pixel, Android 16) → press ▶ Run.
- The emulator has no Bluetooth, so turn on the **demo scale** on the last step of the setup assistant.

**On your phone:**
1. On the phone: Settings → About phone → tap **Build number** 7 times. Then Settings → System → **Developer options** → enable **USB debugging**.
2. Connect the phone by USB and confirm "Allow USB debugging" on the phone.
   - Samsung phones may need the Samsung USB driver.
   - Pixel phones use the *Google USB Driver* (SDK Manager → SDK Tools).
3. Pick your phone in the device dropdown → ▶ Run.

You don't need a Google account or a developer account to install your own app.

### Command line (optional)

```powershell
cd C:\dev\BrewLog\android
.\gradlew.bat assembleDebug          # → app\build\outputs\apk\debug\app-debug.apk
.\gradlew.bat installDebug           # build + install on the connected phone
.\gradlew.bat test                   # 39 unit tests (protocol, analyzer, engine, recipes…)
```

Android Studio's JDK works for the command line: `set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr`.

### Install the APK without a cable

Copy `app-debug.apk` to the phone (cloud drive, USB, e-mail to yourself) and open it. Android asks once to allow installing apps from that source.

## A release build that doesn't expire

Debug builds work fine for personal use. For a smaller, optimised build signed with your own key:

1. Android Studio → Build → **Generate Signed App Bundle / APK** → APK → *Create new…* keystore. Store it **outside** the repo, e.g. `C:\dev\keys\brewlog.jks`, and keep a backup: without it you can't install updates over the existing app.
2. Create `android\keystore.properties` (it's git-ignored):
   ```properties
   storeFile=C:/dev/keys/brewlog.jks
   storePassword=…
   keyAlias=brewlog
   keyPassword=…
   ```
3. Run `.\gradlew.bat assembleRelease` → `app\build\outputs\apk\release\app-release.apk` (about 2 MB, minified with R8).

## Using the BOOKOO scale

Switch the scale on. Brew tab → tap the scale card → allow Bluetooth access → select your scale.
- BrewLog reconnects automatically next time.
- On Android 11 and lower, Location must also be switched on for Bluetooth scanning (an Android requirement; BrewLog doesn't use your location).

## Project structure

```
app/src/main/assets/recipes.json   Built-in recipes (same file as iOS Shared/recipes.json; keep them in sync)
app/src/main/java/com/brewlog/app/
  domain/      Recipes, models, validation, presets, formatting       (pure Kotlin)
  scale/       BOOKOO protocol + validator (pure), BLE ScaleManager, DemoScale
  brewing/     BrewSession: auto-start, pings, countdown, recording  (pure Kotlin)
  analysis/    BrewAnalyzer + GrindRecommender                        (pure Kotlin)
  data/        Settings, JSON repository, brew setup state
  audio/       Synthesized soft cues + haptics
  ui/          Compose theme, components (chart), screens, navigation
app/src/test/  Unit tests: same scenarios and numbers as the iOS tests
```

The pure-Kotlin parts are 1:1 ports of the Swift code, with identical thresholds, suggestion keys and priorities. The shared unit tests guarantee both apps analyse a brew the same way.

## Security & privacy

- **No INTERNET permission.** The app can't reach the network: no accounts, no analytics, no ads.
- **Data stays on the device**, in app-private storage. Cloud backup is excluded (`data_extraction_rules.xml`); phone-to-phone transfer is allowed so your history moves with you.
- **Bluetooth input is untrusted.**
  - Packets are length-, header- and range-checked, and checksums are verified once the firmware is known to use them.
  - Names are sanitized and the scan list is bounded.
  - Only four fixed commands (tare, start, stop and reset the timer) can ever be written to the scale.
- **User input** (recipes, beans, gear, numbers) is sanitized and clamped. Stored data is re-validated when loaded, and file names are restricted to safe IDs.
- **Minified release builds (R8)**; debug logging only in debug builds.
- **The Gradle distribution is checksum-pinned** (`distributionSha256Sum`), and only Google and JetBrains libraries are used.
- **Your keystore and passwords** live outside the repo and in the git-ignored `keystore.properties`.

## Versions

AGP 9.4, Kotlin 2.4, Compose BOM 2026.09, compileSdk 37, targetSdk 36, minSdk 26 (Android 8.0+). Android Studio may offer to update versions later; that's safe to accept.
