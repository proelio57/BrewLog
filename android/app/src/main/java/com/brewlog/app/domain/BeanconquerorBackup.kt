package com.brewlog.app.domain

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.ByteArrayInputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.zip.ZipInputStream
import kotlin.math.roundToInt

/**
 * A parsed Beanconqueror backup (Beanconqueror.zip or Beanconqueror.json).
 * Matches iOS BeanconquerorBackup.swift.
 */
data class BeanconquerorBackup(
    val beans: List<Bean> = emptyList(),
    val mills: List<Mill> = emptyList(),
    val preparations: List<Preparation> = emptyList(),
    val brews: List<Brew> = emptyList(),
    val ratingScale: Double = 5.0,
) {
    data class Bean(
        val uuid: String,
        val name: String,
        val roaster: String,
        val roastingDate: Long?,
        val weight: Double,
        val roast: String,
        val note: String,
        val aromatics: String,
        val finished: Boolean,
        val country: String,
        val region: String,
        val variety: String,
        val processing: String,
    )

    data class Mill(
        val uuid: String,
        val name: String,
        val note: String,
    )

    data class Preparation(
        val uuid: String,
        val name: String,
        val type: String,
        val finished: Boolean,
    )

    data class Brew(
        val uuid: String,
        val date: Long,
        val grindSize: String,
        val dose: Double,
        val preparationID: String,
        val millID: String,
        val beanID: String,
        val temperature: Double,
        val time: Double,
        val water: Double,
        val beverage: Double,
        val rating: Double,
        val note: String,
    )

    fun stars(rating: Double): Int {
        if (rating <= 0 || ratingScale <= 0) return 0
        return (rating / ratingScale * 5.0).roundToInt().coerceIn(1, 5)
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true; isLenient = true }

        fun isZip(data: ByteArray): Boolean {
            return data.size >= 4 &&
                data[0] == 0x50.toByte() &&
                data[1] == 0x4B.toByte() &&
                data[2] == 0x03.toByte() &&
                data[3] == 0x04.toByte()
        }

        fun looksLikeBackup(element: JsonElement): Boolean {
            val obj = element as? JsonObject ?: return false
            return obj.containsKey("BREWS") || obj.containsKey("BEANS")
        }

        @Throws(Exception::class)
        fun parse(data: ByteArray): BeanconquerorBackup {
            if (isZip(data)) return parseZip(data)
            val element = json.parseToJsonElement(data.decodeToString())
            if (!looksLikeBackup(element) || element !is JsonObject) {
                throw IllegalArgumentException("This file is not a Beanconqueror backup.")
            }
            return parseJsonObject(element)
        }

        private fun parseZip(data: ByteArray): BeanconquerorBackup {
            val entries = mutableMapOf<String, ByteArray>()
            ZipInputStream(ByteArrayInputStream(data)).use { zis ->
                var entry = zis.nextEntry
                while (entry != null) {
                    val name = entry.name.substringAfterLast('/')
                    if (!entry.isDirectory && name.endsWith(".json")) {
                        entries[name] = zis.readBytes()
                    }
                    zis.closeEntry()
                    entry = zis.nextEntry
                }
            }

            val mainBytes = entries["Beanconqueror.json"]
                ?: throw IllegalArgumentException("The ZIP file does not contain a Beanconqueror.json.")

            val mainElement = json.parseToJsonElement(mainBytes.decodeToString()) as? JsonObject
                ?: throw IllegalArgumentException("This file is not a valid Beanconqueror JSON.")

            // Handle split backups where chunks are saved as Beanconqueror_Brews_1.json, etc.
            val mergedMap = mainElement.toMutableMap()
            for ((key, fileNamePrefix) in listOf("BREWS" to "Brews", "BEANS" to "Beans")) {
                val currentArray = (mergedMap[key] as? JsonArray)?.toMutableList() ?: mutableListOf()
                var index = 1
                while (true) {
                    val chunkBytes = entries["Beanconqueror_${fileNamePrefix}_$index.json"] ?: break
                    val chunkElement = json.parseToJsonElement(chunkBytes.decodeToString())
                    if (chunkElement is JsonArray) {
                        currentArray.addAll(chunkElement)
                    }
                    index++
                }
                mergedMap[key] = JsonArray(currentArray)
            }

            return parseJsonObject(JsonObject(mergedMap))
        }

        fun parseJsonObject(dict: JsonObject): BeanconquerorBackup {
            var ratingScale = 5.0
            val settingsElement = dict["SETTINGS"]
            val settingsObj = when (settingsElement) {
                is JsonArray -> settingsElement.firstOrNull() as? JsonObject
                is JsonObject -> settingsElement
                else -> null
            }
            settingsObj?.let {
                val scale = number(it["brew_rating"])
                if (scale != null && scale > 0) ratingScale = scale
            }

            val beans = objects(dict["BEANS"]).mapNotNull { item ->
                val uuid = uuid(item) ?: return@mapNotNull null
                val info = objects(item["bean_information"]).firstOrNull() ?: JsonObject(emptyMap())
                Bean(
                    uuid = uuid,
                    name = string(item["name"]),
                    roaster = string(item["roaster"]),
                    roastingDate = date(item["roastingDate"]),
                    weight = number(item["weight"]) ?: 0.0,
                    roast = string(item["roast"]),
                    note = string(item["note"]),
                    aromatics = string(item["aromatics"]),
                    finished = bool(item["finished"]),
                    country = string(info["country"]),
                    region = string(info["region"]),
                    variety = string(info["variety"]),
                    processing = string(info["processing"]),
                )
            }

            val mills = objects(dict["MILL"]).mapNotNull { item ->
                val uuid = uuid(item) ?: return@mapNotNull null
                Mill(uuid = uuid, name = string(item["name"]), note = string(item["note"]))
            }

            val preparations = objects(dict["PREPARATION"]).mapNotNull { item ->
                val uuid = uuid(item) ?: return@mapNotNull null
                Preparation(
                    uuid = uuid,
                    name = string(item["name"]),
                    type = string(item["type"]),
                    finished = bool(item["finished"]),
                )
            }

            val brews = objects(dict["BREWS"]).mapNotNull { item ->
                val uuid = uuid(item) ?: return@mapNotNull null
                val config = item["config"] as? JsonObject ?: JsonObject(emptyMap())
                val timestampSec = number(config["unix_timestamp"]) ?: 0.0
                val dateMillis = if (timestampSec > 0) (timestampSec * 1000).toLong() else System.currentTimeMillis()
                val seconds = (number(item["brew_time"]) ?: 0.0) + (number(item["brew_time_milliseconds"]) ?: 0.0) / 1000.0
                Brew(
                    uuid = uuid,
                    date = dateMillis,
                    grindSize = string(item["grind_size"]),
                    dose = number(item["grind_weight"]) ?: 0.0,
                    preparationID = string(item["method_of_preparation"]),
                    millID = string(item["mill"]),
                    beanID = string(item["bean"]),
                    temperature = number(item["brew_temperature"]) ?: 0.0,
                    time = seconds,
                    water = number(item["brew_quantity"]) ?: 0.0,
                    beverage = number(item["brew_beverage_quantity"]) ?: 0.0,
                    rating = number(item["rating"]) ?: 0.0,
                    note = string(item["note"]),
                )
            }

            return BeanconquerorBackup(
                beans = beans,
                mills = mills,
                preparations = preparations,
                brews = brews,
                ratingScale = ratingScale,
            )
        }

        // Helpers

        fun grindValue(text: String): Double? {
            val cleaned = text.trim().replace(',', '.')
            if (cleaned.isEmpty()) return null
            val value = cleaned.toDoubleOrNull()
            return if (value != null && value.isFinite() && value >= 0) value else null
        }

        fun roastLevel(roast: String): RoastLevel? {
            return when (roast.lowercase()) {
                "cinnamon roast", "new england roast", "half city roast" -> RoastLevel.LIGHT
                "american roast", "moderate-light roast" -> RoastLevel.MEDIUM_LIGHT
                "city roast", "city+ roast" -> RoastLevel.MEDIUM
                "full city roast", "full city + roast" -> RoastLevel.MEDIUM_DARK
                "vienna roast", "french roast", "italian roast" -> RoastLevel.DARK
                else -> null
            }
        }

        fun process(text: String): ProcessMethod? {
            val lower = text.lowercase()
            if (lower.isEmpty()) return null
            return when {
                lower.contains("anaerob") -> ProcessMethod.ANAEROBIC
                lower.contains("honey") -> ProcessMethod.HONEY
                lower.contains("natur") || lower.contains("dry") -> ProcessMethod.NATURAL
                lower.contains("wash") || lower.contains("gewaschen") -> ProcessMethod.WASHED
                else -> ProcessMethod.OTHER
            }
        }

        fun method(type: String): BrewMethod? {
            return when (type.uppercase()) {
                "V60", "ORIGAMI", "KONO", "CAFEC_FLOWER", "HARIO_WOODNECK", "TORNADO_DUO" -> BrewMethod.V60
                "HARIO_SWITCH", "CLEVER" -> BrewMethod.HYBRID
                "KALITA_WAVE", "OREA", "APRIL_BREWER", "DECEMBER_DRIPPER", "BLUE_DRIPPER", "XBLOOM" -> BrewMethod.KALITA
                "CHEMEX", "DRIPPER", "RATIO_SIX_COFFEE_BREWER", "MOCCA_MASTER" -> BrewMethod.UNIVERSAL
                else -> null
            }
        }

        private fun objects(element: JsonElement?): List<JsonObject> {
            return (element as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()
        }

        private fun uuid(item: JsonObject): String? {
            val config = item["config"] as? JsonObject
            val u = string(config?.get("uuid"))
            return if (u.isNotEmpty()) u else null
        }

        private fun string(element: JsonElement?): String {
            if (element == null) return ""
            return element.jsonPrimitive.content.trim()
        }

        private fun number(element: JsonElement?): Double? {
            if (element == null) return null
            element.jsonPrimitive.doubleOrNull?.let { return if (it.isFinite()) it else null }
            return grindValue(element.jsonPrimitive.content)
        }

        private fun bool(element: JsonElement?): Boolean {
            if (element == null) return false
            element.jsonPrimitive.booleanOrNull?.let { return it }
            return element.jsonPrimitive.content.equals("true", ignoreCase = true)
        }

        private fun date(element: JsonElement?): Long? {
            val text = string(element)
            if (text.isEmpty()) return null

            val formats = listOf(
                "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
                "yyyy-MM-dd'T'HH:mm:ssXXX",
                "yyyy-MM-dd'T'HH:mm:ss.SSS",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd",
            )
            for (pattern in formats) {
                try {
                    val sdf = SimpleDateFormat(pattern, Locale.US)
                    sdf.timeZone = TimeZone.getTimeZone("UTC")
                    val parsed = sdf.parse(text)
                    if (parsed != null) return parsed.time
                } catch (_: Exception) {}
            }
            return null
        }
    }
}
