# BrewLog for Android

The Android version of BrewLog: native **Kotlin + Jetpack Compose**, with the same features and the same analysis rules as the iOS app. The folder is self-contained, so you can copy just `android/` to any PC and build it there.

- BOOKOO Themis Mini over Bluetooth LE, or the built-in demo scale
- Guided brewing: auto-start on the first pour, a soft ping just before each target, a chime when each step starts, and a countdown ring
- One chart with weight (left axis) and flow in g/s (right axis) against the recipe curve
- Setup assistant, Quick weigh, recipes (incl. your own), beans, gear (CAFEC/Hario filters, grinder scales), journal
- Rule-based taste feedback with concrete grind suggestions ("go from 24 to 22 clicks"), filter- and roast-aware
- **Brew Editor**: Edit any past brew (dose, water, grind, temperature, gear, recipe, date) with automatic live recalculation of ratio and extraction feedback
- **Full AppData Backup & Restore**: Export full JSON backups of all brews, beans, gear, and custom recipes, and restore them with intelligent deduplication
- **Lock-Screen Brew Timer**: Ongoing status notification during active brewing (parity with iOS Live Activities)
- **Data Importer**: Import Beanconqueror backups (`.json` or `.zip`) and custom recipe JSON files with automatic deduplication
- **Online Recipe Feed**: Automatically fetch and merge curated community and new brewer recipes from GitHub
- **In-App Updater & Sideloading**: Direct APK update check against GitHub Releases with secure `FileProvider` package installation
- **Google Play Store Ready**: R8-minified App Bundle (`.aab`) generation and automated CI pipeline

## One-Command Build Script

You can run the full test suite and build the APK in one command:

```bash
# Build debug APK (runs all unit tests first)
./scripts/build-apk.sh

# Build release APK (R8-minified)
./scripts/build-apk.sh --release
```
The resulting APK is copied to `build/BrewLog-debug.apk` (or `build/BrewLog.apk`).

## Continuous Integration via GitHub Actions

Every push to `main` runs tests and builds the debug APK via `.github/workflows/android.yml`.
Pushing a release tag (e.g. `git tag v1.0.1 && git push origin v1.0.1`) automatically generates a GitHub Release with the APK attached.

## Documentation & Parity Guides

- 📦 **[Google Play Store Publishing Guide](../docs/play-store.md)**: Keystore generation, signing, bundle builds, and review checklist.
- 🤖 **[AI Parity & Maintenance Guide](../docs/ai-parity-guide.md)**: Architecture map and synchronization protocols for Claude, Gemini, and developers.
- 💡 **[Feature Requests & Technical Backlog](../docs/feature-requests.md)**: Zero-knowledge cryptographic sync design and brewing enhancements.

## Command line (Gradle)

```bash
# Run unit tests
./android/gradlew -p android testDebugUnitTest

# Run Android lint
./android/gradlew -p android lintDebug

# Compile Debug APK
./android/gradlew -p android assembleDebug

# Compile Production App Bundle (.aab for Google Play)
./android/gradlew -p android bundleRelease
```

## Security & Privacy

- **No analytics, accounts or third-party ads.**
- **Network access is strictly scoped.** Used exclusively for:
  1. The optional online recipe feed sync (`Settings > Online recipe updates`).
  2. In-app GitHub release checks (`Settings > About & Updates`).
- **All brew data stays on your device**, stored in private app storage.
- **Bluetooth input is strictly validated.** Packets are header-, length- and checksum-checked.
- **Minified release builds (R8)**; debug logging only in debug builds.
- **Keystore and passwords** live in git-ignored `keystore.properties` or encrypted CI secrets.

## Versions

AGP 9.4, Kotlin 2.4, Compose BOM 2026.09, compileSdk 37, targetSdk 36, minSdk 26 (Android 8.0+).
