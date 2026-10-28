package com.brewlog.app

import com.brewlog.app.data.BrewLogBackup
import com.brewlog.app.domain.LabelParser
import com.brewlog.app.domain.LabelParser.Line
import com.brewlog.app.domain.ProcessMethod
import com.brewlog.app.domain.RoastLevel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset

/** Same scenarios as the label scan tests in ToolsTests.swift, plus bean photos in the backup. */
class LabelParserTest {
    private val zone: ZoneId = ZoneOffset.UTC
    private val now: Instant = LocalDateTime.of(2026, 10, 19, 12, 0).atZone(zone).toInstant()
    private fun day(millis: Long?) = millis?.let { Instant.ofEpochMilli(it).atZone(zone).toLocalDate().toString() }

    @Test fun parsesEnglishLabel() {
        val result = LabelParser.parse(listOf(
            Line("Northbound Coffee Roasters", 0.04, 0.05),
            Line("Gesha Village", 0.09, 0.2),
            Line("Bench Maji, Ethiopia", 0.03, 0.32),
            Line("Variety: Gesha 1931", 0.02, 0.4),
            Line("Process: Natural", 0.02, 0.44),
            Line("Tasting notes: jasmine, peach, bergamot", 0.02, 0.5),
            Line("Light roast", 0.02, 0.55),
            Line("Roasted on 02.10.2026", 0.02, 0.6),
            Line("Best before 02.10.2027", 0.02, 0.62),
            Line("Net 250g", 0.02, 0.7),
        ), now, zone)
        assertEquals("Gesha Village", result.name)
        assertEquals("Northbound Coffee Roasters", result.roaster)
        assertEquals("Bench Maji, Ethiopia", result.origin)
        assertEquals("Geisha", result.varietal)
        assertEquals(ProcessMethod.NATURAL, result.process)
        assertEquals(RoastLevel.LIGHT, result.roastLevel)
        assertEquals("2026-10-02", day(result.roastDate))
        assertEquals(250.0, result.bagWeight!!, 0.0)
        assertEquals("jasmine, peach, bergamot", result.tastingNotes)
        assertTrue("roast date" in result.foundFields)
    }

    @Test fun parsesGermanLabel() {
        val result = LabelParser.parse(listOf(
            Line("KAFFEERÖSTEREI MÜLLER", 0.05, 0.02),
            Line("Finca El Paraíso", 0.08, 0.15),
            Line("Kolumbien · Cauca", 0.03, 0.3),
            Line("Aufbereitung: anaerob", 0.02, 0.4),
            Line("Sorte: Castillo, Caturra", 0.02, 0.45),
            Line("Röstdatum", 0.02, 0.5),
            Line("14. Oktober 2026", 0.02, 0.53),
            Line("Filterröstung · 1 kg", 0.02, 0.6),
            Line("Aromen: Erdbeere, Rum, Kakao", 0.02, 0.65),
        ), now, zone)
        assertEquals("Finca El Paraíso", result.name)
        assertEquals("KAFFEERÖSTEREI MÜLLER", result.roaster)
        assertEquals("Kolumbien · Cauca", result.origin)
        assertEquals(ProcessMethod.ANAEROBIC, result.process)
        assertEquals("Castillo, Caturra", result.varietal)
        assertEquals("2026-10-14", day(result.roastDate))
        assertEquals(RoastLevel.LIGHT, result.roastLevel)
        assertEquals(1000.0, result.bagWeight!!, 0.0)
        assertEquals("Erdbeere, Rum, Kakao", result.tastingNotes)
    }

    @Test fun ignoresImplausibleDates() {
        assertNull(LabelParser.date("12.10.2030", now, zone))
        assertNull(LabelParser.date("31.02.2026", now, zone))
        assertNull(LabelParser.date("01.01.2020", now, zone))
        assertEquals("2026-09-30", day(LabelParser.date("2026-09-30", now, zone)))
        assertEquals("2026-10-05", day(LabelParser.date("Oct 5, 2026", now, zone)))
        // Only a best-before date: no roast date
        assertNull(LabelParser.parse(listOf(Line("MHD 01.10.2026")), now, zone).roastDate)
    }

    @Test fun emptyOrJunkLabel() {
        assertTrue(LabelParser.parse(emptyList(), now, zone).isEmpty)
        assertNull(LabelParser.parse(listOf(Line("12345"), Line("  "), Line("www.example.com")), now, zone).name)
        assertNull(LabelParser.bagWeight("Altitude 1900 m"))
        assertNull(LabelParser.bagWeight("20 g per cup... 12000 g"))
        assertEquals(500.0, LabelParser.bagWeight("0,5 kg")!!, 0.0)
        // "Colombia" is a varietal only after a varietal label
        assertNull(LabelParser.varietals("Huila, Colombia"))
        assertEquals("Colombia", LabelParser.varietals("Varietal: Colombia"))
        assertEquals("Pink Bourbon", LabelParser.varietals("Pink Bourbon"))
    }

    @Test fun backupKeepsOnlyRealPhotos() {
        val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 1, 2, 3, 4, 5, 6)
        assertTrue(BrewLogBackup.isPhoto(jpeg))
        assertFalse(BrewLogBackup.isPhoto("not an image at all".toByteArray()))
        val b64 = java.util.Base64.getEncoder().encodeToString(jpeg)
        val text = """{"app":"BrewLog","format":1,"data":{"beans":[{"id":"b1","name":"Gesha"}]},
            "photos":{"b1":"$b64","b2":"bm90IGFuIGltYWdl","b3":42}}"""
        val backup = BrewLogBackup.parse(Json.parseToJsonElement(text) as JsonObject)
        assertEquals(setOf("b1"), backup.photos.keys)
        val again = BrewLogBackup.parse(Json.parseToJsonElement(BrewLogBackup.encode(backup)) as JsonObject)
        assertTrue(again.photos["b1"]!!.contentEquals(jpeg))
    }
}
