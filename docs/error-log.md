# BrewLog Bug & Error Log

Dieser Log erfasst alle aufgetretenen Fehler während der Entwicklung, die Ursachenanalyse und die dazugehörigen Regressionstests, um Wiederholungen zu vermeiden.

---

### [2026-10-14] BrewRepository Directory Parameter & Recipe Template ID Behavior

#### 1. Symptom / Fehler:
- `java.io.FileNotFoundException: .../example_test_repo.json/brewlog.json.tmp (Not a directory)`
- `AssertionError: expected:<0> but was:<1>` in `testRecipeFileExampleTemplateAndImport`

#### 2. Root Cause:
1. `BrewRepository(dir, scope)` erwartet als erstes Argument ein Verzeichnis (`File`), in dem `brewlog.json` abgelegt wird. Wurde fälschlicherweise `tempFolder.newFile(...)` statt `tempFolder.newFolder(...)` übergeben, schlägt das atomare Schreiben (`dir/brewlog.json.tmp`) fehl.
2. Wenn ein Rezept-JSON kein explizites `"id"`-Feld angibt (wie im Standard-Template für neue Rezepte gewollt), generiert `Recipe()` automatisch eine frische UUID (`newId()`). Dadurch wird jeder wiederholte Import eines id-losen Templates als neues Rezept (`recipesAdded = 1`) anstelle einer Aktualisierung (`recipesUpdated = 1`) behandelt.

#### 3. Behebung & Vorbeugung:
1. Im Test wird `tempFolder.newFolder("example_repo")` genutzt.
2. Für das Beispiel-Template `RecipeFile.EXAMPLE_RECIPE_JSON` wird ein stabiles `"id": "template-custom-v60"` vergeben. Dadurch kann das Template wahlweise mit fester ID (für gezielte Updates) oder durch Ändern der ID als neues Rezept importiert werden.
3. Regressionstest `testRecipeFileExampleTemplateAndImport()` validiert beide Aspekte: Stabilität mit ID und Verzeichnis-Handling in `BrewRepository`.

---

### [2026-10-14] Default Catalog Synchronization & Test Coverage for Example Recipes

#### 1. Symptom / Fehler:
- `Unresolved reference 'RecipeLibrary'` und `Unresolved reference 'validated'` beim Hinzufügen der Verifikations-Tests für den Standardkatalog in `DataImporterAndFeedUnitTest.kt`.

#### 2. Root Cause:
- `RecipeLibrary` und die Extension-Methode `Recipe.validated()` aus dem Domain-Package waren in der Testdatei noch nicht importiert.

#### 3. Behebung & Vorbeugung:
1. Explizite Imports `com.brewlog.app.domain.RecipeLibrary` und `com.brewlog.app.domain.validated` in [DataImporterAndFeedUnitTest.kt](file:///home/proelio/Dev/BrewLog-1/android/app/src/test/java/com/brewlog/app/DataImporterAndFeedUnitTest.kt) hinzugefügt.
2. Neuer Regressionstest `testDefaultCatalogIncludesExampleRecipes()` stellt sicher, dass alle Beispiel- und Spezialrezepte (`kasuya-devil-v60`, `orea-v4-big-bloom`, `origami-wave-flow`, `switch-blooming-immersion`, `template-custom-v60`) im Standardkatalog vorhanden, valide und synchronisiert sind.

---

### [2026-10-14] Pressure Monitor BLE Import Resolution & Test Coroutine Environment

#### 1. Symptom / Fehler:
- `Unresolved reference 'BluetoothDevice'` in `PressureManager.kt:204`.
- `Unresolved reference 'Speed'` in `ScaleViews.kt`.
- `Unresolved reference 'test'` in `PressureMonitorUnitTest.kt` (fehlendes `kotlinx-coroutines-test` in Gradle).

#### 2. Root Cause:
1. `BluetoothDevice` Konstanten (`TRANSPORT_LE`) erfordern `android.bluetooth.BluetoothDevice`, das im Manager fehlte.
2. Compose Extended Icons (`Icons.Filled.Speed`) sind Extension Properties im Package `androidx.compose.material.icons.filled.Speed` und können nicht über statischen Pfad ohne Import referenziert werden.
3. Unit-Tests laufen in JVM ohne `kotlinx-coroutines-test`, weshalb `runBlocking` mit Standard-Dispatchern anstelle von `runTest` verwendet werden muss.

#### 3. Behebung & Vorbeugung:
1. `android.bluetooth.BluetoothDevice` in `PressureManager.kt` und `androidx.compose.material.icons.filled.Speed` in `ScaleViews.kt` importiert.
2. `PressureMonitorUnitTest.kt` nutzt `runBlocking` für Coroutine-Prüfungen des `DemoPressureMonitor`.
3. Automatisierte Unit-Tests (`PressureMonitorUnitTest`) und `lintDebug` vor jedem Build ausgeführt und verifiziert.


