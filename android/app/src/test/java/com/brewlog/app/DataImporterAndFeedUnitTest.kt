package com.brewlog.app

import com.brewlog.app.data.AppUpdater
import com.brewlog.app.data.BrewRepository
import com.brewlog.app.data.DataImporter
import com.brewlog.app.data.RecipeFeed
import com.brewlog.app.domain.AppData
import com.brewlog.app.domain.Bean
import com.brewlog.app.domain.BeanconquerorBackup
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.BrewMethod
import com.brewlog.app.domain.Equipment
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.domain.ProcessMethod
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.RecipeFile
import com.brewlog.app.domain.RecipeLibrary
import com.brewlog.app.domain.RecipeStep
import com.brewlog.app.domain.RoastLevel
import com.brewlog.app.domain.StepKind
import com.brewlog.app.domain.TasteProfile
import com.brewlog.app.domain.validated
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class DataImporterAndFeedUnitTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private val testScope = CoroutineScope(Dispatchers.Unconfined)

    @Test
    fun testRecipeFileDecodeAndEncode() {
        val sampleJson = """
            {
              "id": "test-v60",
              "name": "Test V60 Recipe",
              "method": "v60",
              "dose": 15.0,
              "water": 250.0,
              "steps": [
                { "time": 0.0, "water": 50.0, "kind": "bloom", "description": "Bloom" },
                { "time": 45.0, "water": 250.0, "kind": "pour", "description": "Main pour" }
              ]
            }
        """.trimIndent()

        // Decode single recipe
        val decoded = RecipeFile.decode(sampleJson)
        assertEquals(1, decoded.size)
        assertEquals("test-v60", decoded[0].id)
        assertEquals("Test V60 Recipe", decoded[0].name)
        assertEquals(15.0, decoded[0].dose, 0.001)

        // Encode and decode back
        val encoded = RecipeFile.encode(decoded)
        val decodedAgain = RecipeFile.decode(encoded)
        assertEquals(1, decodedAgain.size)
        assertEquals("Test V60 Recipe", decodedAgain[0].name)

        // File name helper
        val fileName = RecipeFile.fileName(decoded)
        assertEquals("Test V60 Recipe.json", fileName)
    }

    @Test
    fun testRecipeFileDecodeListAndWrapper() {
        val listJson = """
            [
              { "id": "r1", "name": "R1", "steps": [{ "time": 0.0, "water": 100.0, "kind": "pour" }] },
              { "id": "r2", "name": "R2", "steps": [{ "time": 0.0, "water": 200.0, "kind": "pour" }] }
            ]
        """.trimIndent()
        val list = RecipeFile.decode(listJson)
        assertEquals(2, list.size)

        val wrapperJson = """
            {
              "recipes": [
                { "id": "r3", "name": "R3", "steps": [{ "time": 0.0, "water": 150.0, "kind": "pour" }] }
              ]
            }
        """.trimIndent()
        val wrapped = RecipeFile.decode(wrapperJson)
        assertEquals(1, wrapped.size)
        assertEquals("R3", wrapped[0].name)
    }

    @Test
    fun testBeanconquerorBackupParseJson() {
        val backupJson = """
            {
              "SETTINGS": { "brew_rating": 5 },
              "BEANS": [
                {
                  "config": { "uuid": "bean-123" },
                  "name": "Ethiopia Yirgacheffe",
                  "roaster": "Square Mile",
                  "roastingDate": "2026-10-01T10:00:00.000Z",
                  "weight": 250,
                  "roast": "cinnamon roast",
                  "note": "Bright and floral",
                  "aromatics": "Jasmine, bergamot",
                  "finished": false,
                  "bean_information": [{
                    "country": "Ethiopia",
                    "region": "Yirgacheffe",
                    "variety": "Heirloom",
                    "processing": "Washed"
                  }]
                }
              ],
              "MILL": [
                {
                  "config": { "uuid": "mill-456" },
                  "name": "Comandante C40",
                  "note": "Red clix"
                }
              ],
              "PREPARATION": [
                {
                  "config": { "uuid": "prep-789" },
                  "name": "Hario V60",
                  "type": "V60",
                  "finished": false
                }
              ],
              "BREWS": [
                {
                  "config": { "uuid": "brew-999", "unix_timestamp": 1792000000 },
                  "bean": "bean-123",
                  "mill": "mill-456",
                  "method_of_preparation": "prep-789",
                  "grind_size": "24",
                  "grind_weight": 15.0,
                  "brew_quantity": 250.0,
                  "brew_time": 150,
                  "brew_time_milliseconds": 500,
                  "brew_temperature": 93.0,
                  "rating": 4.5,
                  "note": "Super delicious"
                }
              ]
            }
        """.trimIndent()

        val backup = BeanconquerorBackup.parse(backupJson.toByteArray())
        assertEquals(1, backup.beans.size)
        assertEquals("Ethiopia Yirgacheffe", backup.beans[0].name)
        assertEquals("Square Mile", backup.beans[0].roaster)
        assertEquals(1, backup.mills.size)
        assertEquals("Comandante C40", backup.mills[0].name)
        assertEquals(1, backup.preparations.size)
        assertEquals("Hario V60", backup.preparations[0].name)
        assertEquals(1, backup.brews.size)

        val b = backup.brews[0]
        assertEquals(15.0, b.dose, 0.001)
        assertEquals(250.0, b.water, 0.001)
        assertEquals(150.5, b.time, 0.001)
        assertEquals(93.0, b.temperature, 0.001)
        assertEquals(5, backup.stars(b.rating))
    }

    @Test
    fun testBeanconquerorBackupParseZip() {
        val jsonContent = """
            {
              "BEANS": [{ "config": { "uuid": "b-1" }, "name": "Zip Bean" }],
              "MILL": [],
              "PREPARATION": [],
              "BREWS": []
            }
        """.trimIndent()

        val baos = ByteArrayOutputStream()
        ZipOutputStream(baos).use { zos ->
            zos.putNextEntry(ZipEntry("Beanconqueror.json"))
            zos.write(jsonContent.toByteArray())
            zos.closeEntry()
        }
        val zipBytes = baos.toByteArray()

        assertTrue(BeanconquerorBackup.isZip(zipBytes))
        val backup = BeanconquerorBackup.parse(zipBytes)
        assertEquals(1, backup.beans.size)
        assertEquals("Zip Bean", backup.beans[0].name)
    }

    @Test
    fun testBeanconquerorMappingHelpers() {
        assertEquals(24.5, BeanconquerorBackup.grindValue("24,5")!!, 0.001)
        assertEquals(18.0, BeanconquerorBackup.grindValue("18")!!, 0.001)
        assertNull(BeanconquerorBackup.grindValue("medium"))

        assertEquals(RoastLevel.LIGHT, BeanconquerorBackup.roastLevel("Cinnamon roast"))
        assertEquals(RoastLevel.DARK, BeanconquerorBackup.roastLevel("French roast"))

        assertEquals(ProcessMethod.WASHED, BeanconquerorBackup.process("Washed / Gewaschen"))
        assertEquals(ProcessMethod.NATURAL, BeanconquerorBackup.process("Dry Natural"))
        assertEquals(ProcessMethod.HONEY, BeanconquerorBackup.process("Yellow Honey"))
        assertEquals(ProcessMethod.ANAEROBIC, BeanconquerorBackup.process("Anaerobic Slow Dry"))

        assertEquals(BrewMethod.V60, BeanconquerorBackup.method("V60"))
        assertEquals(BrewMethod.HYBRID, BeanconquerorBackup.method("HARIO_SWITCH"))
        assertEquals(BrewMethod.KALITA, BeanconquerorBackup.method("KALITA_WAVE"))
    }

    private fun createTestRecipe(
        id: String,
        name: String,
        method: BrewMethod = BrewMethod.V60,
        dose: Double = 15.0,
        water: Double = 250.0,
        steps: List<RecipeStep> = listOf(RecipeStep(kind = StepKind.POUR, time = 0.0, target = water)),
    ) = Recipe(
        id = id,
        name = name,
        author = "BrewLog",
        method = method,
        summary = "Summary for $name",
        tasteNotes = "Balanced and clean",
        taste = TasteProfile(3, 3, 3, 3),
        dose = dose,
        water = water,
        temperature = 93.0,
        grind = "Medium",
        targetTime = 180.0,
        flowMin = 3.0,
        flowMax = 6.0,
        steps = steps,
        tips = emptyList(),
    )

    @Test
    fun testDataImporterIntegration() = runBlocking {
        val repo = BrewRepository(tempFolder.newFolder("repo"), testScope)
        val dummyPreset = createTestRecipe("preset-1", "Preset 1")

        // Import a custom recipe
        val recipeJson = """
            [
              { "id": "custom-1", "name": "My Custom", "steps": [{ "time": 0.0, "water": 200.0, "kind": "pour" }] }
            ]
        """.trimIndent()
        val summary1 = DataImporter.importData(recipeJson.toByteArray(), repo, listOf(dummyPreset))
        assertEquals(1, summary1.recipesAdded)
        assertEquals(0, summary1.recipesUpdated)
        assertEquals(1, repo.data.value.customRecipes.size)

        // Re-import same recipe -> should update
        val summary2 = DataImporter.importData(recipeJson.toByteArray(), repo, listOf(dummyPreset))
        assertEquals(0, summary2.recipesAdded)
        assertEquals(1, summary2.recipesUpdated)

        // Import Beanconqueror backup
        val bcJson = """
            {
              "BEANS": [{ "config": { "uuid": "b-test" }, "name": "BC Bean", "weight": 250 }],
              "MILL": [{ "config": { "uuid": "m-test" }, "name": "BC Grinder" }],
              "PREPARATION": [{ "config": { "uuid": "p-test" }, "name": "BC Brewer", "type": "V60" }],
              "BREWS": [{
                "config": { "uuid": "brew-test", "unix_timestamp": 1700000000 },
                "bean": "b-test",
                "mill": "m-test",
                "method_of_preparation": "p-test",
                "grind_size": "20",
                "grind_weight": 15.0,
                "brew_quantity": 250.0,
                "brew_time": 180,
                "rating": 5
              }]
            }
        """.trimIndent()
        val bcSummary = DataImporter.importData(bcJson.toByteArray(), repo, listOf(dummyPreset))
        assertEquals(1, bcSummary.beans)
        assertEquals(1, bcSummary.grinders)
        assertEquals(1, bcSummary.brewers)
        assertEquals(1, bcSummary.brews)
        assertEquals(0, bcSummary.skippedBrews)

        // Deduplication test: re-import same backup
        val bcSummary2 = DataImporter.importData(bcJson.toByteArray(), repo, listOf(dummyPreset))
        assertEquals(0, bcSummary2.brews)
        assertEquals(1, bcSummary2.skippedBrews)
    }

    @Test
    fun testRecipeFeedMerge() {
        val bundled = listOf(
            createTestRecipe("p1", "Preset One", BrewMethod.V60, 15.0, 250.0),
            createTestRecipe("p2", "Preset Two", BrewMethod.V60, 18.0, 300.0),
        )
        val remote = listOf(
            // Updated version of p1
            createTestRecipe("p1", "Preset One Updated", BrewMethod.V60, 15.0, 250.0),
            // Brand new preset
            createTestRecipe("p3", "Preset Three Online", BrewMethod.KALITA, 20.0, 320.0),
        )

        val merged = RecipeFeed.merge(bundled, remote)
        assertEquals(3, merged.size)
        assertEquals("p1", merged[0].id)
        assertEquals("Preset One Updated", merged[0].name)
        assertEquals("p2", merged[1].id)
        assertEquals("Preset Two", merged[1].name)
        assertEquals("p3", merged[2].id)
        assertEquals("Preset Three Online", merged[2].name)
        assertNull(merged[2].isCustom)
    }

    @Test
    fun testAppUpdaterVersionComparison() {
        assertTrue(AppUpdater.isNewer("1.0", "1.1"))
        assertTrue(AppUpdater.isNewer("1.0.4", "1.0.5"))
        assertTrue(AppUpdater.isNewer("1.0.9", "1.1.0"))
        assertTrue(AppUpdater.isNewer("1.0", "2.0"))

        assertFalse(AppUpdater.isNewer("1.0.5", "1.0.4"))
        assertFalse(AppUpdater.isNewer("1.0.4", "1.0.4"))
        assertFalse(AppUpdater.isNewer("2.0.0", "1.9.9"))
    }

    @Test
    fun testExportAndImportAppDataBackup() = runBlocking {
        val repo = BrewRepository(tempFolder.newFolder("backup-repo"), testScope)
        val dummyPreset = createTestRecipe("preset-1", "Preset 1")

        // Seed initial data in repo
        val testBean = Bean(id = "bean-1", name = "Geisha", roaster = "Specialty Roasters", bagWeight = 250.0)
        val testGear = Equipment(id = "gear-1", name = "Ode Gen 2", type = EquipmentType.GRINDER)
        val testBrew = Brew(id = "brew-1", date = 1700000000000L, recipeId = "preset-1", recipeName = "Preset 1", dose = 15.0, targetWater = 250.0)
        val customRecipe = createTestRecipe("custom-1", "My Special Recipe")

        repo.update { current ->
            current.copy(
                beans = listOf(testBean),
                equipment = listOf(testGear),
                brews = listOf(testBrew),
                customRecipes = listOf(customRecipe)
            )
        }

        // 1. Export backup JSON
        val exportedJson = DataImporter.exportBackup(repo)
        assertNotNull(exportedJson)
        assertTrue(exportedJson.contains("Geisha"))
        assertTrue(exportedJson.contains("Ode Gen 2"))
        assertTrue(exportedJson.contains("My Special Recipe"))

        // 2. Import into a fresh repo
        val newRepo = BrewRepository(tempFolder.newFolder("restore-repo"), testScope)
        val summary = DataImporter.importData(exportedJson.toByteArray(), newRepo, listOf(dummyPreset))

        assertEquals(1, summary.beans)
        assertEquals(1, summary.grinders)
        assertEquals(1, summary.brews)
        assertEquals(1, summary.recipesAdded)

        val restoredData = newRepo.data.value
        assertEquals(1, restoredData.beans.size)
        assertEquals("Geisha", restoredData.beans[0].name)
        assertEquals(1, restoredData.equipment.size)
        assertEquals("Ode Gen 2", restoredData.equipment[0].name)
        assertEquals(1, restoredData.brews.size)
        assertEquals(15.0, restoredData.brews[0].dose, 0.001)
        assertEquals(1, restoredData.customRecipes.size)
        assertEquals("My Special Recipe", restoredData.customRecipes[0].name)

        // 3. Re-import into same repo -> deduplication check
        val summary2 = DataImporter.importData(exportedJson.toByteArray(), newRepo, listOf(dummyPreset))
        assertEquals(0, summary2.beans)
        assertEquals(0, summary2.grinders)
        assertEquals(0, summary2.brews)
        assertEquals(1, summary2.skippedBrews)
        assertEquals(0, summary2.recipesAdded)
        assertEquals(1, summary2.recipesUpdated)
    }

    @Test
    fun testSampleImportFilesIntegrity() = runBlocking {
        val samplesDir = File("../../samples/recipes")
        if (!samplesDir.exists()) return@runBlocking

        val repo = BrewRepository(tempFolder.newFolder("sample-import-repo"), testScope)
        val dummyPreset = createTestRecipe("preset-1", "Preset 1")

        // 1. Test single recipe sample
        val singleFile = File(samplesDir, "single-recipe-v60-devil.json")
        assertTrue("single-recipe-v60-devil.json should exist", singleFile.exists())
        val singleSummary = DataImporter.importData(singleFile.readBytes(), repo, listOf(dummyPreset))
        assertEquals(1, singleSummary.recipesAdded)
        assertEquals(1, repo.data.value.customRecipes.size)
        assertEquals("Kasuya Devil's Recipe", repo.data.value.customRecipes[0].name)

        // 2. Test multi recipe pack
        val multiFile = File(samplesDir, "sample-brewers-pack.json")
        assertTrue("sample-brewers-pack.json should exist", multiFile.exists())
        val multiSummary = DataImporter.importData(multiFile.readBytes(), repo, listOf(dummyPreset))
        assertEquals(3, multiSummary.recipesAdded)
        assertEquals(4, repo.data.value.customRecipes.size)

        // 3. Test full AppData backup restore
        val fullBackupFile = File(samplesDir, "sample-full-brewlog-backup.json")
        assertTrue("sample-full-brewlog-backup.json should exist", fullBackupFile.exists())
        val backupSummary = DataImporter.importData(fullBackupFile.readBytes(), repo, listOf(dummyPreset))
        assertEquals(1, backupSummary.beans)
        assertEquals(1, backupSummary.brewers)
        assertEquals(1, backupSummary.grinders)
        assertEquals(1, backupSummary.brews)
        assertEquals(1, backupSummary.recipesAdded)
        assertEquals(5, repo.data.value.customRecipes.size)

        val data = repo.data.value
        assertEquals("Panama Geisha Natural", data.beans[0].name)
        assertEquals(2, data.equipment.size)
        assertEquals(1, data.brews.size)
        assertEquals("Lance Hedrick 1-2-1 V60", data.brews[0].recipeName)
    }

    @Test
    fun testDeploymentAndConfigurationIntegrity() {
        // 1. Verify build-apk.sh exists and is executable
        val buildScript = File("../../scripts/build-apk.sh")
        if (buildScript.exists()) {
            assertTrue("build-apk.sh should be executable", buildScript.canExecute())
        }

        // 2. Verify AndroidManifest permissions and file_paths resource
        val manifestFile = File("src/main/AndroidManifest.xml")
        if (manifestFile.exists()) {
            val manifestText = manifestFile.readText()
            assertTrue(manifestText.contains("android.permission.INTERNET"))
            assertTrue(manifestText.contains("android.permission.REQUEST_INSTALL_PACKAGES"))
            assertTrue(manifestText.contains("android.permission.POST_NOTIFICATIONS"))
            assertTrue(manifestText.contains("androidx.core.content.FileProvider"))
        }

        // 3. Verify file_paths.xml exists
        val filePaths = File("src/main/res/xml/file_paths.xml")
        if (filePaths.exists()) {
            val content = filePaths.readText()
            assertTrue(content.contains("cache-path"))
        }
    }

    @Test
    fun testRecipeFileExampleTemplateAndImport() = runBlocking {
        // 1. Verify example filename
        assertTrue(RecipeFile.EXAMPLE_FILE_NAME.endsWith(".json"))

        // 2. Decode the template
        val decoded = RecipeFile.decode(RecipeFile.EXAMPLE_RECIPE_JSON)
        assertEquals(1, decoded.size)
        val template = decoded.first()
        assertEquals("My Custom Pour-Over", template.name)
        assertEquals(BrewMethod.V60, template.method)
        assertEquals(15.0, template.dose, 0.001)
        assertEquals(250.0, template.water, 0.001)
        assertEquals(93.0, template.temperature, 0.001)
        assertEquals(4, template.steps.size)
        assertEquals(StepKind.BLOOM, template.steps[0].kind)
        assertEquals(50.0, template.steps[0].target ?: 0.0, 0.001)
        assertEquals(150.0, template.steps[1].target ?: 0.0, 0.001)
        assertEquals(250.0, template.steps[2].target ?: 0.0, 0.001)
        assertEquals(StepKind.REMOVE, template.steps[3].kind)
        assertEquals(4, template.taste.acidity)
        assertEquals(4, template.taste.sweetness)
        assertTrue(template.tips.isNotEmpty())

        // 3. Test DataImporter importing this example JSON
        val repoDir = tempFolder.newFolder("example_repo")
        val repo = BrewRepository(repoDir, testScope)
        val summary = DataImporter.importData(RecipeFile.EXAMPLE_RECIPE_JSON.toByteArray(), repo, emptyList())
        assertEquals(1, summary.recipesAdded)
        assertEquals(0, summary.recipesUpdated)

        val customRecipes = repo.data.value.customRecipes
        assertEquals(1, customRecipes.size)
        assertEquals("My Custom Pour-Over", customRecipes[0].name)
        assertTrue(customRecipes[0].isCustom == true)

        // 4. Re-importing updates the recipe rather than duplicating
        val summary2 = DataImporter.importData(RecipeFile.EXAMPLE_RECIPE_JSON.toByteArray(), repo, emptyList())
        assertEquals(0, summary2.recipesAdded)
        assertEquals(1, summary2.recipesUpdated)
        assertEquals(1, repo.data.value.customRecipes.size)
    }

    @Test
    fun testDefaultCatalogIncludesExampleRecipes() {
        val assetFile = File("src/main/assets/recipes.json")
        assertTrue("recipes.json asset file must exist", assetFile.exists())
        val catalog = RecipeLibrary.parse(assetFile.readText())
        val catalogIds = catalog.map { it.id }.toSet()

        val expectedExampleIds = setOf(
            "kasuya-devil-v60",
            "orea-v4-big-bloom",
            "origami-wave-flow",
            "switch-blooming-immersion",
            "template-custom-v60",
        )

        for (id in expectedExampleIds) {
            assertTrue("Default catalog must include $id", catalogIds.contains(id))
            val recipe = catalog.first { it.id == id }
            assertTrue("Recipe $id must have non-empty name", recipe.name.isNotBlank())
            assertTrue("Recipe $id must have non-empty author", recipe.author.isNotBlank())
            assertTrue("Recipe $id must have steps", recipe.steps.isNotEmpty())
            assertEquals("Recipe $id must equal validated", recipe, recipe.validated())
        }
    }
}


