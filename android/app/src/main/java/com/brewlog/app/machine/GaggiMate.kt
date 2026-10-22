package com.brewlog.app.machine

import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.StepKind
import com.brewlog.app.domain.roundHalfAway
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import java.util.Locale

// Port of MachineStatus.swift / gaggimate.ts: GaggiMate's WebSocket protocol (docs/websocket-api.yaml in
// jniebuhr/gaggimate). No Android dependencies; unit-testable on the JVM.

/** Live state of a GaggiMate controller, merged from its partial `evt:status` frames. */
data class GaggiMateStatus(
    val temperature: Double? = null,
    val targetTemperature: Double? = null,
    val pressure: Double? = null,
    val targetPressure: Double? = null,
    val flow: Double? = null,
    /** 0 standby, 1 brew, 2 steam, 3 water, 4 grind. */
    val mode: Int? = null,
    val profile: String? = null,
    val hasPressure: Boolean? = null,
    val processActive: Boolean = false,
    /** "brew", "infusion" or "grind". */
    val processKind: String? = null,
    val processLabel: String? = null,
    val processIsUtility: Boolean = false,
    /** Weight from the scale connected to GaggiMate. */
    val weight: Double? = null,
    val scaleConnected: Boolean = false,
    val systemState: String? = null,
    val systemMessage: String? = null,
) {
    /** A shot is running (pre-infusion or extraction), not a flush or grind. */
    val isBrewing: Boolean get() = processActive && !processIsUtility && (processKind == "brew" || processKind == "infusion")

    val hasWeight: Boolean get() = scaleConnected && weight != null

    /** Missing keys keep their value, null clears it. Numbers are clamped to sane ranges. */
    fun merge(frame: JsonObject): GaggiMateStatus {
        fun number(key: String, current: Double?, lo: Double, hi: Double): Double? {
            if (key !in frame) return current
            val value = (frame[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
            return value?.takeIf { it.isFinite() }?.coerceIn(lo, hi)
        }
        fun text(element: JsonElement?, max: Int): String? = (element as? JsonPrimitive)?.takeIf { it.isString }?.content?.take(max)

        var next = copy(
            temperature = number("ct", temperature, 0.0, 200.0),
            targetTemperature = number("tt", targetTemperature, 0.0, 200.0),
            pressure = number("pr", pressure, 0.0, 20.0),
            targetPressure = number("pt", targetPressure, 0.0, 20.0),
            flow = number("fl", flow, 0.0, 30.0),
            weight = number("cw", weight, -100.0, 5000.0),
        )
        if ("m" in frame) next = next.copy(mode = (frame["m"] as? JsonPrimitive)?.intOrNull)
        if ("p" in frame) next = next.copy(profile = text(frame["p"], 80))
        if ("cp" in frame) next = next.copy(hasPressure = (frame["cp"] as? JsonPrimitive)?.booleanOrNull)
        if ("bc" in frame) next = next.copy(scaleConnected = (frame["bc"] as? JsonPrimitive)?.booleanOrNull == true)
        (frame["sys"] as? JsonObject)?.let { sys ->
            next = next.copy(systemState = text(sys["s"], 20), systemMessage = text(sys["m"], 200))
        }
        if ("process" in frame) {
            val process = frame["process"] as? JsonObject
            next = if (process != null) {
                next.copy(
                    processActive = (process["a"] as? JsonPrimitive)?.intOrNull == 1,
                    processKind = text(process["s"], 20),
                    processLabel = text(process["l"], 80),
                    processIsUtility = (process["u"] as? JsonPrimitive)?.intOrNull == 1,
                )
            } else {
                next.copy(processActive = false, processKind = null, processLabel = null, processIsUtility = false)
            }
        }
        return next
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /** Parses a WebSocket text message into a JSON object (null for anything else or anything too large). */
        fun parseMessage(text: String): JsonObject? {
            if (text.length > 256 * 1024) return null
            return try {
                json.parseToJsonElement(text) as? JsonObject
            } catch (e: Exception) {
                null
            }
        }

        /** The frame if the message is an `evt:status`. */
        fun statusFrame(text: String): JsonObject? {
            if (text.length > 64 * 1024) return null
            val obj = parseMessage(text) ?: return null
            return if ((obj["tp"] as? JsonPrimitive)?.content == "evt:status") obj else null
        }

        /** True if the frame carries live readings (as opposed to the slow state). */
        fun isTelemetry(frame: JsonObject): Boolean = "pr" in frame || "ct" in frame
    }
}

enum class MachineMode(val value: Int, val title: String) {
    STANDBY(0, "Standby"), BREW(1, "Brew"), STEAM(2, "Steam"), WATER(3, "Water"),
}

object GaggiMateProfile {
    const val LABEL_PREFIX = "BrewLog · "

    /** Builds a GaggiMate profile (schema/profile.json in the GaggiMate repo) from an espresso recipe. */
    fun make(recipe: Recipe, dose: Double, temperature: Double, hasPressure: Boolean, hasScale: Boolean): JsonObject {
        val yieldGrams = roundHalfAway(recipe.scaled(dose).water)
        val extractStart = recipe.steps.firstOrNull { it.kind == StepKind.EXTRACT }?.time ?: 0.0
        val preinfusion = if (hasPressure) roundHalfAway(maxOf(extractStart - 2, 0.0)) else 0.0
        val pressure = (recipe.pressure ?: 9.0).coerceIn(1.0, 12.0)
        val phases = buildJsonArray {
            if (preinfusion >= 1) {
                add(buildJsonObject {
                    put("name", "Pre-infusion"); put("phase", "preinfusion"); put("valve", 1); put("duration", preinfusion)
                    putJsonObject("pump") { put("target", "pressure"); put("pressure", 3); put("flow", 4) }
                })
            }
            add(buildJsonObject {
                put("name", "Extraction"); put("phase", "brew"); put("valve", 1)
                // With a scale the weight ends the shot and the duration is only a safety cap.
                put("duration", if (hasScale) roundHalfAway(recipe.targetTime + 20) else roundHalfAway(maxOf(recipe.targetTime - preinfusion, 5.0)))
                if (hasPressure) {
                    putJsonObject("pump") { put("target", "pressure"); put("pressure", pressure); put("flow", 0) }
                    putJsonObject("transition") { put("type", "linear"); put("duration", 2); put("adaptive", true) }
                } else {
                    put("pump", 100)
                }
                if (hasScale) {
                    put("targets", buildJsonArray {
                        add(buildJsonObject { put("type", "volumetric"); put("operator", "gte"); put("value", yieldGrams) })
                    })
                }
            })
        }
        return buildJsonObject {
            put("label", (LABEL_PREFIX + recipe.name).take(60))
            put("type", "pro")
            put("description", String.format(Locale.US, "From BrewLog: %.1f g in, %.0f g out, about %.0f s.", dose, yieldGrams, recipe.targetTime))
            put("temperature", roundHalfAway(temperature).coerceIn(80.0, 100.0))
            put("dose", dose.coerceIn(1.0, 100.0))
            put("phases", phases)
        }
    }
}

/** "gaggimate.local", "192.168.1.20", "http://gaggimate.local/" → ws URL; null for anything else. */
fun gaggiMateUrl(input: String): String? {
    var host = input.trim().lowercase(Locale.ROOT)
    for (prefix in listOf("http://", "https://", "ws://", "wss://")) if (host.startsWith(prefix)) host = host.removePrefix(prefix)
    while (host.endsWith("/")) host = host.dropLast(1)
    if (host.endsWith("/ws")) host = host.dropLast(3)
    if (host.isEmpty() || host.length > 253 || !host.all { it in 'a'..'z' || it in '0'..'9' || it == '.' || it == '-' || it == ':' }) return null
    return "ws://$host/ws"
}
