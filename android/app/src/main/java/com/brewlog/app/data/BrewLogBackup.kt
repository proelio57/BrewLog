package com.brewlog.app.data

import com.brewlog.app.domain.AppData
import com.brewlog.app.domain.InputLimits
import com.brewlog.app.domain.MachineSample
import com.brewlog.app.domain.WeightSample
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import java.time.Instant

/**
 * The wrapped BrewLog backup shared by iOS, Android and web (docs/data-formats.md, "BrewLog backup"):
 * `{ app, format, exportedAt, data, samples, machine }`. Port of BrewLogBackup.swift.
 */
data class BrewLogBackup(
    val data: AppData,
    val samples: Map<String, List<WeightSample>> = emptyMap(),
    val machine: Map<String, List<MachineSample>> = emptyMap(),
    /** Bean photos (JPEG or PNG) by bean id. */
    val photos: Map<String, ByteArray> = emptyMap(),
) {
    companion object {
        /** Samples per brew: 30 min at 10 Hz, like the live recorder. */
        val MAX_SAMPLES = (InputLimits.MAX_BREW_SECONDS * 10).toInt() + 10

        private val json = Json { ignoreUnknownKeys = true; isLenient = true }
        private val pretty = Json { prettyPrint = true; ignoreUnknownKeys = true; encodeDefaults = true }
        private val compact = Json { explicitNulls = false }

        const val MAX_PHOTO_BYTES = 2_000_000

        /** A JPEG or PNG of at most 2 MB (anything else in `photos` is ignored). */
        fun isPhoto(bytes: ByteArray): Boolean {
            if (bytes.size <= 8 || bytes.size > MAX_PHOTO_BYTES) return false
            val jpeg = bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() && bytes[2] == 0xFF.toByte()
            val png = bytes[0] == 0x89.toByte() && bytes[1] == 0x50.toByte() && bytes[2] == 0x4E.toByte() && bytes[3] == 0x47.toByte()
            return jpeg || png
        }

        fun isWrapped(element: JsonObject): Boolean =
            (element["app"] as? JsonPrimitive)?.content == "BrewLog" && element["data"] is JsonObject

        fun parse(element: JsonObject): BrewLogBackup {
            val data = json.decodeFromJsonElement<AppData>(element["data"] as JsonObject)
            val samples = (element["samples"] as? JsonObject)?.mapNotNull { (id, value) ->
                parseWeights(value)?.let { id to it }
            }?.toMap().orEmpty()
            val machine = (element["machine"] as? JsonObject)?.mapNotNull { (id, value) ->
                parseMachine(value)?.let { id to it }
            }?.toMap().orEmpty()
            val photos = (element["photos"] as? JsonObject)?.mapNotNull { (id, value) ->
                val text = (value as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return@mapNotNull null
                if (id.length > 120 || text.length > MAX_PHOTO_BYTES * 4 / 3 + 8) return@mapNotNull null
                val bytes = runCatching { java.util.Base64.getMimeDecoder().decode(text) }.getOrNull() ?: return@mapNotNull null
                if (isPhoto(bytes)) id to bytes else null
            }?.toMap().orEmpty()
            return BrewLogBackup(data, samples, machine, photos)
        }

        /** `[[seconds, grams], …]`, `{t, w}` objects are read too. Out-of-range points are dropped. */
        fun parseWeights(value: JsonElement): List<WeightSample>? {
            val array = value as? JsonArray ?: return null
            return array.asSequence().mapNotNull { point ->
                val (t, w) = when (point) {
                    is JsonArray -> point.getOrNull(0).number() to point.getOrNull(1).number()
                    is JsonObject -> point["t"].number() to point["w"].number()
                    else -> null to null
                }
                if (t == null || w == null || t < 0 || t > InputLimits.MAX_BREW_SECONDS || w < -100 || w > InputLimits.MAX_WATER * 2) null
                else WeightSample(t, w)
            }.take(MAX_SAMPLES).toList()
        }

        /** `[{t, p, c, f}, …]`: seconds, bar, °C, ml/s. */
        fun parseMachine(value: JsonElement): List<MachineSample>? {
            val array = value as? JsonArray ?: return null
            return array.asSequence().mapNotNull { point ->
                val o = point as? JsonObject ?: return@mapNotNull null
                val t = o["t"].number() ?: return@mapNotNull null
                val p = o["p"].number() ?: return@mapNotNull null
                if (t < 0 || t > InputLimits.MAX_BREW_SECONDS || p < 0 || p > 20) return@mapNotNull null
                MachineSample(t, p, o["c"].number()?.takeIf { it in 0.0..150.0 }, o["f"].number()?.takeIf { it in 0.0..20.0 })
            }.take(MAX_SAMPLES).toList()
        }

        private fun JsonElement?.number(): Double? = (this as? JsonPrimitive)?.doubleOrNull?.takeIf { it.isFinite() }

        /** Pretty-printed, so a backup in Git shows readable diffs. */
        fun encode(backup: BrewLogBackup, exportedAt: Instant = Instant.now()): String {
            val root = buildJsonObject {
                put("app", "BrewLog")
                put("format", 1)
                put("exportedAt", exportedAt.toString())
                put("data", pretty.encodeToJsonElement(AppData.serializer(), backup.data))
                putJsonObject("samples") {
                    for ((id, points) in backup.samples) if (points.isNotEmpty()) {
                        put(id, buildJsonArray { points.forEach { add(buildJsonArray { add(JsonPrimitive(it.t)); add(JsonPrimitive(it.w)) }) } })
                    }
                }
                if (backup.photos.isNotEmpty()) putJsonObject("photos") {
                    for ((id, bytes) in backup.photos) if (isPhoto(bytes)) put(id, java.util.Base64.getEncoder().encodeToString(bytes))
                }
                putJsonObject("machine") {
                    for ((id, points) in backup.machine) if (points.isNotEmpty()) {
                        put(id, compact.encodeToJsonElement(kotlinx.serialization.builtins.ListSerializer(MachineSample.serializer()), points))
                    }
                }
            }
            return pretty.encodeToString(JsonElement.serializer(), root)
        }
    }
}
