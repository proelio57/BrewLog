# BrewLog Feature Requests & Technical Backlog

This document collects architectural designs, feature requests, and future enhancements for BrewLog across Android, iOS, and Web. Features are prioritized based on user privacy, brewing workflow quality, and technical feasibility.

---

## 1. High Priority Architectural Feature: Accountless Zero-Knowledge Sync & Restore

### Problem Statement
Currently, BrewLog is 100% offline-first and stores all user data (journal entries, bean inventory, grinders, brewers, custom recipes, grind dial settings) locally on the device.
If a user changes phones, loses their device, or uninstalls and reinstalls the app:
- Local SQLite/JSON data is erased.
- Unless the user manually exported a JSON backup to their file manager or Google Drive/iCloud, their journal history is lost.
- Traditional cloud accounts (requiring email, passwords, Google/Apple OAuth, cloud servers with personal data) introduce severe privacy, telemetry, security breach, and maintenance liabilities.

### The Solution: Zero-Knowledge Cryptographic Hash / Sync Key
A privacy-first, accountless sync system where user identity and encryption are rooted in a cryptographic key held solely by the user.

```
+-----------------------------------------------------------------------------------+
|                                  USER DEVICE                                      |
|                                                                                   |
|  [ User Secret / Recovery Key ]                                                    |
|  (e.g., "brew-7a9f-3bc1-d4e5-912a" or 12-word BIP-39 mnemonic phrase)             |
|          |                                                                        |
|          +---> PBKDF2 / Argon2id (Salt: "BrewLog-ZeroKnowledge-v1")              |
|                     |                                                             |
|                     +---> [ Sync ID ] = HMAC-SHA256(Key, "lookup-token")          |
|                     |     (Public storage index only)                             |
|                     |                                                             |
|                     +---> [ Encryption Key ] = HMAC-SHA256(Key, "payload-cipher")|
|                           (256-bit AES-GCM Key - NEVER LEAVES THE DEVICE)         |
|                                                                                   |
|  [ Local AppData JSON ]                                                           |
|       |                                                                           |
|       v                                                                           |
|  [ AES-256-GCM Encrypt + GZIP ] ---> [ Ciphertext Blob + IV + Auth Tag ]         |
+---------------------------------------------------|-------------------------------+
                                                    | HTTPS POST
                                                    v
+-----------------------------------------------------------------------------------+
|                        ZERO-KNOWLEDGE STORAGE BACKEND                             |
|                                                                                   |
|   Bucket / Key-Value Record:                                                      |
|   {                                                                               |
|     "id": "<Sync ID>",                                                            |
|     "blob": "<base64 AES-GCM ciphertext>",                                        |
|     "updatedAt": 1792000000                                                       |
|   }                                                                               |
|                                                                                   |
|   * Server CANNOT inspect recipes, beans, notes, or brews.                        |
|   * Zero user emails, passwords, trackers, or identities are stored.             |
+-----------------------------------------------------------------------------------+
```

### Detailed Cryptographic Specification

1. **Secret Generation:**
   - On first setup, the app generates 128 bits of cryptographically secure random entropy (`java.security.SecureRandom` on Android, `SecRandomCopyBytes` on iOS).
   - Displayed to the user in two formats:
     - **Sync Hash Key:** `brew-XXXX-XXXX-XXXX-XXXX` (Base32/Hex formatted with dashes for easy typing).
     - **12-Word Mnemonic Phrase:** Standard BIP-39 English dictionary words for paper backup.
     - **QR Code:** For quick optical transfer between devices (e.g. migrating from iPhone to Android).

2. **Key Derivation:**
   - Algorithm: PBKDF2 with HMAC-SHA256 (min 100,000 iterations) or Argon2id.
   - Salt: Fixed application domain salt combined with entropy version.
   - Output splits via HKDF into:
     - `SyncIdentifier` (16 bytes, Hex): Public document identifier for cloud lookup.
     - `PayloadKey` (32 bytes / 256 bits): Symmetric encryption key. Stored securely in `EncryptedSharedPreferences` / `Android Keystore` on Android, and `Keychain` on iOS.

3. **Encryption & Transmission:**
   - Plaintext payload: `AppData` encoded to JSON, compressed using GZIP.
   - Symmetric Cipher: `AES-256-GCM` with a fresh 12-byte initialization vector (IV) per sync.
   - Integrity: 128-bit GCM authentication tag prevents ciphertext tampering or corruption.

4. **Storage Options (Pluggable):**
   - **Default Relay:** Cloudflare Workers KV or lightweight AWS S3 / DynamoDB endpoint that acts as an opaque blob store.
   - **Self-Hosted / BYOC:** WebDAV (Nextcloud / ownCloud) or encrypted GitHub Private Gist for power users who want 100% self-hosted ownership.

5. **Restoration & Reinstall Flow:**
   1. User installs a fresh copy of BrewLog on Android or iOS.
   2. On onboarding or in *Settings > Backup & Sync*, user chooses **"Restore with Sync Key"**.
   3. User enters their 16-character key, scans a QR code, or enters the 12 words.
   4. The client computes `SyncIdentifier`, requests the latest encrypted blob from the endpoint.
   5. Client decrypts the blob locally with `PayloadKey`.
   6. Data is loaded and merged into `BrewRepository` using the existing idempotent deduplication logic in `DataImporter.importAppData`.

6. **Conflict Resolution:**
   - Non-destructive union: Brews and beans are keyed by timestamp and unique UUIDs. Existing records are preserved, new records are added, and modified recipes update gracefully.

---

## 2. Brewing & Extraction Enhancements

### Water Chemistry & Mineral Target Calculator

> **Status:** Done on iOS (Gear → Tools → Water recipes; water profiles per brew). Presets: SCA, Rao, Barista Hustle, Hendon, WoC Budapest, Melbourne. Commercial drops (Lotus) not included. Android/web open, see `docs/data-formats.md`.
- **Description:** Provide a water formulation assistant for mineralizing distilled / reverse-osmosis (RO) water.
- **Features:**
  - Presets: SCA Standard (150 mg/L TDS, 40 mg/L alkalinity, 68 mg/L calcium hardness), Barista Hustle recipes, Rao Water, Lotus Coffee drops.
  - Custom DIY recipes: Input concentrated Epsom salt ($MgSO_4$), Baking soda ($NaHCO_3$), and Calcium chloride ($CaCl_2$) drops to hit target GH/KH.
  - Water profile selector attached to brews in the journal.

### Refractometer & Extraction Yield (EY%) Calculator

> **Status:** Done on iOS (TDS on each brew, calculator under Gear → Tools, control chart). Android/web open.
- **Description:** Allow coffee enthusiasts with digital refractometers to evaluate extraction efficiency.
- **Formulas:**
  $$\text{Extraction Yield (\%)} = \frac{\text{Beverage Weight (g)} \times \text{TDS (\%)}}{\text{Dry Coffee Dose (g)}}$$
  $$\text{Brew Ratio} = \frac{\text{Water (g)}}{\text{Dose (g)}}$$
- **UI:** Interactive coffee brewing chart mapping TDS against Extraction Yield (under-extracted, balanced, over-extracted).

### Audio / Voice Step Prompts

> **Status:** Done on iOS (Settings → Voice, AVSpeechSynthesizer, English prompts). Android/web open.
- **Description:** Optional voice synthesis during active brewing so the barista does not need to look at the screen while pouring.
- **Example Prompts:**
  - *"Pour to 60 grams for bloom."*
  - *"Main pour to 250 grams in 3, 2, 1."*
  - *"Swirl gently and let draw down."*

---

## 3. Hardware & Sensor Integrations

### Smart BLE Kettle Integration
- **Supported Brands:** Fellow Stagg EKG+, Timemore Smart Fish Kettle, Decent Kettle.
- **Features:**
  - Read current water temperature directly over Bluetooth Low Energy.
  - Automatically populate water temperature in brew setup and journal.
  - Alert when water hits target brew temperature.

### Additional BLE Coffee Scales
- **Current:** Bookoo Themis / Mini (Fully supported via Bluetooth LE).
- **Candidates for Expansion:**
  - Acaia (Lunar, Pearl, Cinco) via standard Acaia Bluetooth protocol.
  - Timemore Black Mirror Basic / Nano Bluetooth models.
  - Felicita Arc / Incline.
  - DiFluid Microbalance.

### BOOKOO Espresso Monitor (Real-Time Pressure Profiling & Dual-Device BLE)

- **Device Reference:** [BOOKOO Espresso Monitor](https://de.bookoocoffee.com/products/bookoo-espresso-monitor?shpxid=b3cf5a4a-3eda-4360-9bd8-e4d944aa192c) – Digital pressure sensor with G1/8 / M6 threads for espresso machines (E61, manual levers like Flair 58, Cafelat Robot, Decent).
- **Protocol Analysis:**
  - Standardized BooKoo BLE transmission architecture (documented in [BooKooCode/OpenSource](https://github.com/BooKooCode/OpenSource/blob/main/espresso_monitor/protocols.md) and field-tested in Beanconqueror).
  - **Service UUID:** `00000fff-0000-1000-8000-00805f9b34fb` (16-bit: `0x0FFF`)
  - **Extraction / Pressure Data Characteristic UUID:** `0000ff02-0000-1000-8000-00805f9b34fb` (16-bit: `0xFF02`, notifications enabled via standard CCCD `0x2902`)
  - **Command Characteristic UUID:** `0000ff01-0000-1000-8000-00805f9b34fb` (16-bit: `0xFF01`)
  - **Checksum Calculation:** XOR over transmission packet bytes (`CheckSum = Header1 ^ Header2 ^ Data0 ^ ... ^ DataN`).
  - **Data Telemetry:** Real-time extraction pressure in bar (0.00–16.00 bar, 0.01 bar resolution), internal timestamp in milliseconds, battery level (%), and extraction status.
  - **Safe Command Set:** Start extraction, stop extraction, zero/tare pressure sensor.

- **Dual-Device Parallel Bluetooth Architecture:**
  - Modern smartphones (Android 8+ and iOS CoreBluetooth) natively support multiple concurrent peripheral BLE connections (up to 7–8 simultaneous devices).
  - **Concurrent Stream Management:**
    - Device 1 (`ScaleManager`): Connects to the coffee scale (e.g. BooKoo Themis Mini) $\rightarrow$ streams Weight ($g$) and Flow Rate ($g/s$).
    - Device 2 (`PressureManager`): Connects to the pressure transducer (BooKoo Espresso Monitor) $\rightarrow$ streams Pressure ($bar$).
  - **Monotonic Phase Synchronization:** Both data streams emit timestamps aligned to a unified monotonic clock (`System.nanoTime()` / `CACurrentMediaTime()`). This prevents drift and guarantees sample-accurate alignment between flow and pressure curves.

- **Dynamic Conditional UI & Multi-Axis Graphing:**
  - **Zero-Clutter Invariant:** The pressure curve and pressure metrics are **completely hidden by default**. They do NOT clutter standard pour-over or single-scale espresso workflows.
  - **Display Conditions:** The pressure gauge and chart line appear **IF AND ONLY IF**:
    1. The user enables *Espresso Pressure Monitoring* in *Settings / Gear*, **AND**
    2. A compatible pressure monitor is actively connected via Bluetooth.
  - **Live Brewing Graph:**
    - Primary Y-Axis (Left): Brew weight ($g$) and Flow Rate ($g/s$).
    - Secondary Y-Axis (Right): Real-time Pressure in bar ($0$ to $12+$ bar), rendered in a distinctive high-contrast color (e.g. amber/copper or vivid cyan).
  - **Smart Extraction Trigger (Auto-Start Timer):**
    - Configurable pressure threshold (e.g. $> 0.5$ bar): Automatically starts the shot timer when pre-infusion pressure begins to rise, eliminating manual button taps while pulling shots on a lever machine.

- **Data Model & Persistence:**
  - `data class PressurePoint(val timeMillis: Long, val bar: Double)`
  - Extend `Brew` model with optional `pressureCurve: List<PressurePoint>? = null`.
  - Stored in local JSON/SQLite and exported seamlessly in BrewLog and Beanconqueror backup files.

### Smartwatch Companion (Wear OS & watchOS)
- **Features:**
  - Wrist-based brew timer synchronized with the phone.
  - Haptic buzz / tap at the start of each pour step.
  - Target weight and elapsed time glanceable on wrist.

---

## 4. Bean Inventory & Smart Scanning

### On-Device OCR Label Scanner

> **Status:** Done on iOS (bean editor → Scan label, Apple Vision, English and German labels). Android (ML Kit) open.
- **Description:** Take a picture of a coffee bean bag and automatically extract metadata into a new Bean profile.
- **Technology:**
  - Android: Google ML Kit Text Recognition (runs 100% on-device, zero cloud uploads).
  - iOS: Apple Vision Framework (`VNRecognizeTextRequest`).
- **Detected Fields:**
  - Roaster name, bean name/origin (country & region), process method (Washed, Natural, Anaerobic, Honey), varietal (Geisha, Bourbon, SL28), and roast date.

### Bean Bag & Roast Photos

> **Status:** Done on iOS: photo per bean (camera or library), roast-tinted placeholder, thumbnails in the bean list, brew setup and brew detail. Stored as downsampled JPEG in SwiftData external storage (not a separate file per bean) and exported inline as base64 (`photos` in the backup). Android/web open.
- **Description:** Allow users to capture or select a photo of their coffee bag or roasted beans for each bean cellar entry.
- **Visual Design & UX:**
  - **Custom Image:** When a photo is attached, display an edge-rounded thumbnail in the Bean Cellar, Brew Setup screen, and Brew Detail history card.
  - **Fallback Placeholder:** If no photo is selected, render a stylized coffee bean / pouch vector icon with a dynamic background tint that reflects the roast level (e.g., light honey for Light Roast, warm amber for Medium, rich roasted umber for Dark Roast).
- **Technical Architecture & Storage:**
  - **Local App-Private Storage:** Save images in private internal storage (`context.filesDir/beans/{beanId}.webp` on Android, `Documents/beans/{beanId}.jpg` on iOS).
  - **Automatic Optimization:** Downsample pictures on import to max 1024×1024 at 80% compression (saving disk space and ensuring 60fps scrolling in Compose/SwiftUI lists).
  - **Backup Integrity:** Allow exporting with images in a `.zip` bundle (similar to Beanconqueror backup archives) or inline Base64 data for lightweight single-file sharing.

### Universal Grinder Click & Dial Conversion Matrix

> **Status:** Done on iOS as a calibration model rather than a fixed matrix: Gear → Tools → Grind converter, plus the recipe's µm range shown on the selected grinder. Built-in calibrations for Comandante C40, 1Zpresso K-Ultra and ZP6, Kingrinder K6; other grinders get `µm per step` + filter starting point in their settings. Android/web open.
- **Description:** A reference tool to translate grind settings across different popular grinders.
- **Supported Grinders:** Comandante C40 (clicks), Fellow Ode Gen 1/2, Timemore C2/C3/Chestnut, Baratza Encore ESP, 1Zpresso (JX, K-Ultra, ZP6), DF64, Niche Zero.
- **Benefit:** When sharing a recipe with a friend or importing a community recipe, automatically map "24 clicks on Comandante" to "4.2 on Ode Gen 2".

