package com.brewlog.app

import com.brewlog.app.data.BrewLogBackup
import com.brewlog.app.data.BrewRepository
import com.brewlog.app.data.DataImporter
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.MachineSample
import com.brewlog.app.domain.WeightSample
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** The wrapped backup from iOS / web (docs/data-formats.md, "BrewLog backup") with weight and pressure curves. */
class BrewLogBackupTest {
    @get:Rule val tempFolder = TemporaryFolder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)

    private val iosBackup = """
        {
          "app": "BrewLog", "format": 1, "exportedAt": "2026-10-17T08:00:00.000Z",
          "data": {
            "version": 1,
            "beans": [{ "id": "b1", "name": "Ethiopia Guji", "roaster": "Test", "bagWeight": 250, "remaining": 200,
                        "photoIgnoredByAndroid": true }],
            "equipment": [],
            "brews": [
              { "id": "brew-a", "date": 1792000000000, "recipeId": "espresso-classic", "recipeName": "Classic", "dose": 18,
                "targetWater": 36, "finalWeight": 36.4, "totalTime": 28, "tds": 9.1, "rating": 4, "feedback": ["sour"] },
              { "id": "brew-b", "date": 1792000100000, "recipeId": "rao-v60", "recipeName": "Rao V60", "dose": 15, "targetWater": 250 }
            ],
            "customRecipes": []
          },
          "samples": {
            "brew-a": [[0, 0], [5.5, 2.1], [28, 36.4]],
            "brew-b": [{ "t": 0, "w": 0 }, { "t": 30, "w": 60 }, [-5, 10], ["x", 1], [99999, 1]]
          },
          "machine": { "brew-a": [{ "t": 0, "p": 1.5, "c": 92.5, "f": 2.1 }, { "t": 1, "p": 8.8 }, { "t": 2, "p": 999 }] },
          "photos": { "b1": "AAAA" }
        }
    """.trimIndent()

    @Test fun parsesCurvesAndDropsJunkPoints() {
        val backup = BrewLogBackup.parse(Json.parseToJsonElement(iosBackup) as JsonObject)
        assertEquals(2, backup.data.brews.size)
        assertEquals(listOf(WeightSample(0.0, 0.0), WeightSample(5.5, 2.1), WeightSample(28.0, 36.4)), backup.samples["brew-a"])
        // {t, w} objects are read, negative / out-of-range / non-numeric points are dropped.
        assertEquals(listOf(WeightSample(0.0, 0.0), WeightSample(30.0, 60.0)), backup.samples["brew-b"])
        assertEquals(listOf(MachineSample(0.0, 1.5, 92.5, 2.1), MachineSample(1.0, 8.8)), backup.machine["brew-a"])
    }

    @Test fun importsTheWrappedBackupWithCurvesOnce() {
        val repo = BrewRepository(tempFolder.newFolder("repo"), scope)
        val summary = DataImporter.importData(iosBackup.toByteArray(), repo, emptyList())
        assertEquals(1, summary.beans)
        assertEquals(2, summary.brews)
        assertEquals(3, repo.samples("brew-a").size)
        assertEquals(listOf(MachineSample(0.0, 1.5, 92.5, 2.1), MachineSample(1.0, 8.8)), repo.machineSamples("brew-a"))
        // Importing the same file again adds nothing.
        val again = DataImporter.importData(iosBackup.toByteArray(), repo, emptyList())
        assertEquals(0, again.brews)
        assertEquals(2, again.skippedBrews)
        assertEquals(2, repo.data.value.brews.size)
    }

    @Test fun exportIsTheWrappedFormatAndRoundTrips() {
        val repo = BrewRepository(tempFolder.newFolder("source"), scope)
        repo.saveNewBrew(
            Brew(id = "shot-1", date = 1792000000000L, recipeId = "espresso-classic", recipeName = "Classic", dose = 18.0, targetWater = 36.0),
            listOf(WeightSample(0.0, 0.0), WeightSample(25.0, 36.0)),
            listOf(MachineSample(0.0, 2.0), MachineSample(0.2, 6.5, 93.0)),
        )
        val text = DataImporter.exportBackup(repo)
        val root = Json.parseToJsonElement(text).jsonObject
        assertEquals("BrewLog", root["app"]!!.jsonPrimitive.content)
        assertEquals(1, root["format"]!!.jsonPrimitive.content.toInt())
        assertTrue(root["data"] is JsonObject)
        assertTrue("machine samples omit missing values", !text.contains("\"c\": null"))

        val target = BrewRepository(tempFolder.newFolder("target"), scope)
        val summary = DataImporter.importData(text.toByteArray(), target, emptyList())
        assertEquals(1, summary.brews)
        assertEquals(listOf(WeightSample(0.0, 0.0), WeightSample(25.0, 36.0)), target.samples("shot-1"))
        assertEquals(listOf(MachineSample(0.0, 2.0), MachineSample(0.2, 6.5, 93.0)), target.machineSamples("shot-1"))
    }
}
