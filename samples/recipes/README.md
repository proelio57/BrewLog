# BrewLog Import Test Samples

This directory provides curated test files to test and verify the BrewLog import and restore functionality across Android, iOS, and Web.

## Available Sample Files

| File | Format | Contents & Verification Target |
| :--- | :--- | :--- |
| **[`single-recipe-v60-devil.json`](single-recipe-v60-devil.json)** | Single Recipe Object | Tests single-object JSON import (*Tetsu Kasuya's Devil's Recipe* for low-bitterness dark roasts). Verifies single-recipe parsing, custom recipe creation, and duplicate updates. |
| **[`sample-brewers-pack.json`](sample-brewers-pack.json)** | JSON Array (`[...]`) | Tests multi-recipe bundle import. Contains 3 specialty recipes for **Orea V4**, **Origami**, and **Hario Switch**. Verifies batch ingestion and deduplication. |
| **[`sample-full-brewlog-backup.json`](sample-full-brewlog-backup.json)** | Full `AppData` JSON | Tests full zero-loss backup restore: includes Coffee Beans (*Panama Geisha Natural*), Equipment (*Origami Dripper M* & *Comandante C40 MK4*), Custom Recipes, and a logged Brew with rating and notes. |

---

## How to Test in the App

### Option A: Via App UI
1. Open BrewLog on your device or emulator.
2. Navigate to **Journal** or **Recipes**.
3. Tap the **⋮** options menu in the top right corner.
4. Select **"Import backup / recipes…"**.
5. Choose one of the sample `.json` files.
6. The app will display an import summary (e.g. *"Imported 3 new recipes"* or *"Imported 1 brew, 1 bean, 2 grinders/brewers"*).

### Option B: Push to Android Emulator & Open via ADB
To test loading directly on the running Android emulator:
```bash
# Push sample files to emulator download folder:
$HOME/Android/Sdk/platform-tools/adb push samples/recipes /sdcard/Download/
```
