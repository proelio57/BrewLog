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
- **Description:** Provide a water formulation assistant for mineralizing distilled / reverse-osmosis (RO) water.
- **Features:**
  - Presets: SCA Standard (150 mg/L TDS, 40 mg/L alkalinity, 68 mg/L calcium hardness), Barista Hustle recipes, Rao Water, Lotus Coffee drops.
  - Custom DIY recipes: Input concentrated Epsom salt ($MgSO_4$), Baking soda ($NaHCO_3$), and Calcium chloride ($CaCl_2$) drops to hit target GH/KH.
  - Water profile selector attached to brews in the journal.

### Refractometer & Extraction Yield (EY%) Calculator
- **Description:** Allow coffee enthusiasts with digital refractometers to evaluate extraction efficiency.
- **Formulas:**
  $$\text{Extraction Yield (\%)} = \frac{\text{Beverage Weight (g)} \times \text{TDS (\%)}}{\text{Dry Coffee Dose (g)}}$$
  $$\text{Brew Ratio} = \frac{\text{Water (g)}}{\text{Dose (g)}}$$
- **UI:** Interactive coffee brewing chart mapping TDS against Extraction Yield (under-extracted, balanced, over-extracted).

### Audio / Voice Step Prompts
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

### Smartwatch Companion (Wear OS & watchOS)
- **Features:**
  - Wrist-based brew timer synchronized with the phone.
  - Haptic buzz / tap at the start of each pour step.
  - Target weight and elapsed time glanceable on wrist.

---

## 4. Bean Inventory & Smart Scanning

### On-Device OCR Label Scanner
- **Description:** Take a picture of a coffee bean bag and automatically extract metadata into a new Bean profile.
- **Technology:**
  - Android: Google ML Kit Text Recognition (runs 100% on-device, zero cloud uploads).
  - iOS: Apple Vision Framework (`VNRecognizeTextRequest`).
- **Detected Fields:**
  - Roaster name, bean name/origin (country & region), process method (Washed, Natural, Anaerobic, Honey), varietal (Geisha, Bourbon, SL28), and roast date.

### Bean Bag & Roast Photos
- **Description:** Allow users to capture or select a photo of their coffee bag or roasted beans for each bean cellar entry.
- **Visual Design & UX:**
  - **Custom Image:** When a photo is attached, display an edge-rounded thumbnail in the Bean Cellar, Brew Setup screen, and Brew Detail history card.
  - **Fallback Placeholder:** If no photo is selected, render a stylized coffee bean / pouch vector icon with a dynamic background tint that reflects the roast level (e.g., light honey for Light Roast, warm amber for Medium, rich roasted umber for Dark Roast).
- **Technical Architecture & Storage:**
  - **Local App-Private Storage:** Save images in private internal storage (`context.filesDir/beans/{beanId}.webp` on Android, `Documents/beans/{beanId}.jpg` on iOS).
  - **Automatic Optimization:** Downsample pictures on import to max 1024×1024 at 80% compression (saving disk space and ensuring 60fps scrolling in Compose/SwiftUI lists).
  - **Backup Integrity:** Allow exporting with images in a `.zip` bundle (similar to Beanconqueror backup archives) or inline Base64 data for lightweight single-file sharing.

### Universal Grinder Click & Dial Conversion Matrix
- **Description:** A reference tool to translate grind settings across different popular grinders.
- **Supported Grinders:** Comandante C40 (clicks), Fellow Ode Gen 1/2, Timemore C2/C3/Chestnut, Baratza Encore ESP, 1Zpresso (JX, K-Ultra, ZP6), DF64, Niche Zero.
- **Benefit:** When sharing a recipe with a friend or importing a community recipe, automatically map "24 clicks on Comandante" to "4.2 on Ode Gen 2".

