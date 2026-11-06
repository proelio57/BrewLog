package com.brewlog.app.machine

import com.brewlog.app.domain.BrewMethod
import com.brewlog.app.domain.InputLimits
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.RecipeLibrary
import com.brewlog.app.domain.RecipeStep
import com.brewlog.app.domain.StepKind
import com.brewlog.app.domain.validated
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import java.util.UUID
import kotlin.math.roundToInt

/**
 * A profile stored on the GaggiMate (or demo machine), as the profile picker shows it.
 */
data class MachineProfileSummary(
    /** GaggiMate's profile id, used to select it. */
    val id: String,
    /** Without BrewLog's "BrewLog · " prefix. */
    val label: String,
    val isSelected: Boolean,
    val isFavorite: Boolean,
    /** A profile BrewLog sent (its recipe is already in BrewLog). */
    val isBrewLogs: Boolean,
    /** The profile as an espresso recipe; null if it can't be read as one. */
    val recipe: Recipe?,
)

/**
 * Turns GaggiMate profiles (schema `profile.json` in the GaggiMate repo) into BrewLog espresso recipes.
 * Port of Machine/GaggiMateProfileImport.swift.
 */
object GaggiMateProfileImport {
    const val RECIPE_ID_PREFIX = "gaggimate-"
    const val LABEL_PREFIX = GaggiMateProfile.LABEL_PREFIX

    /** True if the JSON is one GaggiMate profile, a list of them or `{ "profiles": [...] }`. */
    fun looksLikeProfiles(element: JsonElement): Boolean {
        if (element is JsonObject) {
            val list = element["profiles"] as? JsonArray
            if (list != null) return list.isNotEmpty() && list.all { isProfile(it) }
            return isProfile(element)
        }
        if (element is JsonArray) {
            return element.isNotEmpty() && element.all { isProfile(it) }
        }
        return false
    }

    private fun isProfile(element: JsonElement): Boolean {
        if (element !is JsonObject) return false
        if (element["phases"] !is JsonArray) return false
        val label = element["label"] as? JsonPrimitive ?: return false
        if (!label.isString) return false
        // BrewLog recipes have "steps", GaggiMate profiles "label" and "phases".
        return element["steps"] == null
    }

    /** All usable profiles in the JSON as recipes. Utility profiles (flush, descale) are left out. */
    fun recipes(element: JsonElement): List<Recipe> {
        val list: List<JsonElement> = when {
            element is JsonObject && element["profiles"] is JsonArray -> element["profiles"] as JsonArray
            element is JsonObject -> listOf(element)
            element is JsonArray -> element
            else -> emptyList()
        }
        return list.take(200).mapNotNull { (it as? JsonObject)?.let { obj -> recipe(obj) } }
    }

    /**
     * The machine's `res:profiles:list` answer for the profile picker: selected first, then favorites,
     * then the rest, each in the machine's order. Utility profiles and entries without an id are left out.
     */
    fun summaries(response: JsonObject): List<MachineProfileSummary> {
        val list = (response["profiles"] as? JsonArray)?.take(200) ?: emptyList()
        val all = list.mapNotNull { item ->
            val profile = item as? JsonObject ?: return@mapNotNull null
            if ((profile["utility"] as? JsonPrimitive)?.booleanOrNull == true) return@mapNotNull null
            val id = (profile["id"] as? JsonPrimitive)?.content?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            var label = (profile["label"] as? JsonPrimitive)?.content?.take(InputLimits.MAX_NAME_LENGTH)?.trim()
                ?: return@mapNotNull null
            if (label.isEmpty()) return@mapNotNull null
            val isBrewLogs = label.startsWith(LABEL_PREFIX)
            if (isBrewLogs) label = label.removePrefix(LABEL_PREFIX)
            MachineProfileSummary(
                id = id,
                label = label,
                isSelected = (profile["selected"] as? JsonPrimitive)?.booleanOrNull == true,
                isFavorite = (profile["favorite"] as? JsonPrimitive)?.booleanOrNull == true,
                isBrewLogs = isBrewLogs,
                recipe = recipe(profile),
            )
        }
        return all.filter { it.isSelected } +
                all.filter { !it.isSelected && it.isFavorite } +
                all.filter { !it.isSelected && !it.isFavorite }
    }

    /** One profile as an espresso recipe, or null if it has no phases or is a utility profile. */
    fun recipe(profile: JsonObject): Recipe? {
        if ((profile["utility"] as? JsonPrimitive)?.booleanOrNull == true) return null
        val rawPhases = (profile["phases"] as? JsonArray)?.takeIf { it.isNotEmpty() } ?: return null
        var label = (profile["label"] as? JsonPrimitive)?.content?.trim() ?: return null
        if (label.isEmpty()) return null
        if (label.startsWith(LABEL_PREFIX)) label = label.removePrefix(LABEL_PREFIX)
        val phases = rawPhases.take(InputLimits.MAX_STEPS).mapNotNull { (it as? JsonObject)?.let { obj -> Phase(obj) } }
        if (phases.isEmpty()) return null

        val dose = (number(profile["dose"]) ?: 18.0).coerceIn(5.0, 40.0)
        // A weight target wins; otherwise a ratio target (yield = dose * ratio); otherwise 1:2.
        val lastWeight = phases.mapNotNull { it.volumetricTarget }.lastOrNull()
        val lastRatio = phases.mapNotNull { it.ratioTarget }.lastOrNull()?.let { it * dose }
        val yield = (lastWeight ?: lastRatio)?.let { ((it.coerceIn(5.0, 200.0) * 10).roundToInt() / 10.0) }
            ?: ((dose * 20).roundToInt() / 10.0) // to 0.1 g, not whole grams

        val preinfusion = phases.filter { it.isPreinfusion }.sumOf { it.duration }
        val total = phases.sumOf { it.duration }
        val hasWeightTarget = phases.any { it.volumetricTarget != null || it.ratioTarget != null }
        val time = (if (hasWeightTarget) minOf(total, preinfusion + 25.0) else total).coerceIn(15.0, 120.0).roundToInt().toDouble()
        val pressure = phases.filter { !it.isPreinfusion }.mapNotNull { it.pressure }.maxOrNull()
            ?: phases.mapNotNull { it.pressure }.maxOrNull() ?: 9.0

        val steps = mutableListOf<RecipeStep>()
        if (preinfusion >= 1.0) {
            steps.add(
                RecipeStep(
                    kind = StepKind.PREINFUSE,
                    time = 0.0,
                    target = null,
                    valve = null,
                    note = phases.filter { it.isPreinfusion }.joinToString(", ") { it.summary },
                )
            )
        }
        steps.add(
            RecipeStep(
                kind = StepKind.EXTRACT,
                time = if (preinfusion >= 1.0) preinfusion.roundToInt().toDouble() else 0.0,
                target = yield,
                valve = null,
                note = phases.filter { !it.isPreinfusion }.joinToString(", ") { it.summary },
            )
        )

        val id = (profile["id"] as? JsonPrimitive)?.content?.take(60)?.takeIf { it.isNotEmpty() } ?: slug(label)
        val description = (profile["description"] as? JsonPrimitive)?.content?.trim() ?: ""
        val blank = RecipeLibrary.blankRecipe()

        val recipe = Recipe(
            id = RECIPE_ID_PREFIX + id,
            name = label,
            author = "GaggiMate",
            method = BrewMethod.ESPRESSO,
            summary = description.ifEmpty { "Imported from a GaggiMate profile." },
            tasteNotes = "",
            taste = blank.taste,
            dose = dose,
            water = yield,
            temperature = (number(profile["temperature"]) ?: 93.0).coerceIn(80.0, 100.0),
            grind = "",
            targetTime = time,
            flowMin = 1.0,
            flowMax = 2.5,
            steps = steps,
            tips = phases.mapIndexed { idx, p -> "Phase ${idx + 1}: ${p.summary}" },
            isCustom = true,
            pressure = pressure.coerceIn(1.0, 12.0),
        )
        return recipe.validated()
    }

    private class Phase(raw: JsonObject) {
        val name: String = (raw["name"] as? JsonPrimitive)?.content?.take(40) ?: ""
        val isPreinfusion: Boolean = (raw["phase"] as? JsonPrimitive)?.content == "preinfusion"
        val duration: Double = (number(raw["duration"]) ?: 0.0).coerceIn(0.0, 300.0)
        var pressure: Double? = null
        var flow: Double? = null
        var power: Double? = null
        var holds: String? = null
        val volumetricTarget: Double?
        val ratioTarget: Double?

        init {
            val pumpObj = raw["pump"] as? JsonObject
            if (pumpObj != null) {
                val target = (pumpObj["target"] as? JsonPrimitive)?.content
                val rawPressure = number(pumpObj["pressure"])
                val rawFlow = number(pumpObj["flow"])
                val p = rawPressure?.takeIf { it >= 0 }?.coerceIn(0.0, 15.0)
                val fl = rawFlow?.takeIf { it >= 0 }?.coerceIn(0.0, 15.0)
                val targetVal = if (target == "flow") rawFlow else rawPressure
                if (targetVal != null && targetVal < 0) {
                    holds = if (target == "flow") "flow" else "pressure"
                }
                if (target == "flow") {
                    this.flow = fl
                    this.pressure = p?.takeIf { it > 0 }
                } else {
                    this.pressure = p
                }
            } else {
                val pwr = number(raw["pump"])
                if (pwr != null) {
                    this.power = pwr.coerceIn(0.0, 100.0)
                }
            }

            val targets = raw["targets"] as? JsonArray ?: emptyList()
            fun targetValue(type: String): Double? {
                for (t in targets) {
                    val obj = t as? JsonObject ?: continue
                    if ((obj["type"] as? JsonPrimitive)?.content == type) {
                        val v = number(obj["value"])
                        if (v != null && v > 0) return v
                    }
                }
                return null
            }
            volumetricTarget = targetValue("volumetric")
            ratioTarget = targetValue("ratio")
        }

        val summary: String
            get() {
                val parts = mutableListOf(name.ifEmpty { if (isPreinfusion) "Pre-infusion" else "Brew" })
                if (duration > 0) parts.add("${format(duration)} s")
                if (holds != null) {
                    parts.add("hold $holds")
                } else if (flow != null) {
                    parts.add("${format(flow!!)} ml/s" + (pressure?.let { ", max ${format(it)} bar" } ?: ""))
                } else if (pressure != null) {
                    parts.add("${format(pressure!!)} bar")
                } else if (power != null) {
                    parts.add("pump ${format(power!!)} %")
                }
                if (volumetricTarget != null) {
                    parts.add("to ${format(volumetricTarget)} g")
                } else if (ratioTarget != null) {
                    parts.add("to 1:${format(ratioTarget)}")
                }
                return parts.joinToString(" · ")
            }

        private fun format(value: Double): String =
            if (value == value.roundToInt().toDouble()) value.roundToInt().toString()
            else String.format(java.util.Locale.US, "%.1f", value)
    }

    private fun number(element: JsonElement?): Double? {
        val prim = element as? JsonPrimitive ?: return null
        return prim.doubleOrNull?.takeIf { it.isFinite() }
    }

    private fun slug(text: String): String {
        val slug = text.lowercase(java.util.Locale.ROOT)
            .map { if (it.isLetterOrDigit()) it else '-' }
            .joinToString("")
            .split("-")
            .filter { it.isNotEmpty() }
            .joinToString("-")
        return if (slug.isEmpty()) UUID.randomUUID().toString() else slug.take(60)
    }
}
