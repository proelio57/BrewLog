# Publishing BrewLog to Google Play Store

This guide walks you through signing, bundling, and publishing BrewLog to the Google Play Store, as well as setting up automated updates via GitHub.

---

## 1. Prerequisites & Keystore Generation

Google Play requires all release builds (Android App Bundles `.aab`) to be cryptographically signed with an upload key.

### 1.1 Generate Your Upload Keystore

Run the following command in your terminal to generate a secure keystore:

```bash
keytool -genkey -v \
  -keystore android/brewlog-upload-key.jks \
  -alias brewlog \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

Store this keystore in a safe place and **never commit `.jks` files to git**.

### 1.2 Configure Local Keystore Signing

Create `android/keystore.properties` (this file is already in `.gitignore`):

```properties
storeFile=../brewlog-upload-key.jks
storePassword=YOUR_KEYSTORE_PASSWORD
keyAlias=brewlog
keyPassword=YOUR_KEY_PASSWORD
```

---

## 2. Building the Production Release Bundle (.aab)

Google Play mandates the **Android App Bundle (`.aab`)** format for all new app submissions.

### 2.1 Run Tests & Build the Bundle

BrewLog enforces running the unit test suite and lint checks before building:

```bash
# 1. Run unit tests
./android/gradlew -p android testDebugUnitTest

# 2. Compile optimized, R8-shrunk App Bundle
./android/gradlew -p android bundleRelease
```

The signed `.aab` file will be generated at:
`android/app/build/outputs/bundle/release/app-release.aab`

---

## 3. Google Play Console Setup

1. **Create Developer Account**:
   - Register at [Google Play Console](https://play.google.com/console).
   - Pay the one-time registration fee ($25).

2. **Create New App**:
   - Click **Create App**.
   - App Name: `BrewLog` (or `BrewLog - Coffee Companion`).
   - Default Language: English (or German).
   - App or Game: **App**.
   - Free or Paid: **Free**.

3. **Complete Store Presence**:
   - **Short description**: Clean, private specialty coffee journal and pour-over timer.
   - **Full description**: Mention zero ads, zero trackers, offline-first, Beanconqueror backup support, recipe scaling, and custom pour curves.
   - **Screenshots**: Upload high-res phone screenshots of the Timer, Journal, Brew Detail, and Recipe Library.
   - **App Icon**: 512×512 PNG (can be exported from `BrewLog/Assets.xcassets/AppIcon.appiconset/AppIcon.png`).

4. **Data Safety & Privacy Policy**:
   - **Does your app collect or share user data?**: Select **No**.
   - BrewLog stores all coffee journals, grinders, beans, and recipes locally on the device (`Encrypted / private local storage`).
   - Internet access is strictly used for optional recipe feed synchronization and checking GitHub for updates when sideloaded.
   - Provide a privacy policy URL (e.g. your GitHub repository's `README.md` or a hosted page on GitHub Pages).

5. **Release Tracks**:
   - Start with **Internal testing** or **Closed testing** track.
   - Upload `app-release.aab`.
   - Add testers or invite yourself via email to test the Play Store installation on your device.
   - Once tested, promote to **Production**.

---

## 4. In-App Updates vs. Google Play Developer Policy

> [!IMPORTANT]
> **Google Play Developer Distribution Agreement (Section 4.5)** strictly prohibits apps installed via Google Play from downloading and installing executable `.apk` binaries from external third-party sources (such as GitHub Releases).
>
> - **Sideloaded APKs (GitHub / Direct download)**: Use the built-in **In-App Updater** (`Settings > About & Updates > Check for updates`), which downloads new `.apk` assets directly from GitHub Releases and triggers Android's package installer via `FileProvider`.
> - **Google Play Releases**: Once installed from Google Play, updates are distributed seamlessly and automatically through the Google Play Store client itself.

---

## 5. Automated CI/CD via GitHub Actions

When you push code or tags to GitHub, `.github/workflows/android.yml` automatically:
1. Validates code and executes all unit tests.
2. Builds the debug APK and release bundle.
3. Automatically publishes releases and attaches `BrewLog-debug.apk` and `BrewLog.aab` to GitHub Releases whenever a Git tag is pushed (e.g. `git tag v1.0.1 && git push origin v1.0.1`).

### Optional: Automating Signed Builds in GitHub Actions
To produce signed APKs and bundles in GitHub Actions, add these repository secrets in **GitHub > Settings > Secrets and variables > Actions**:
- `KEYSTORE_BASE64`: Output of `base64 -w 0 android/brewlog-upload-key.jks`
- `KEYSTORE_PASSWORD`: Keystore password
- `KEY_ALIAS`: `brewlog`
- `KEY_PASSWORD`: Key password
