package com.brewlog.app.data

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.RecipeLibrary

/** The brew being configured on the Brew tab. Remembers your last choices. Port of BrewSetup (BrewLogApp.swift). */
class BrewSetupState(private val prefs: SharedPreferences, presets: List<Recipe>) {
    var recipe: Recipe by mutableStateOf(
        presets.firstOrNull { it.id == prefs.getString(KEY_RECIPE, null) } ?: presets.firstOrNull() ?: RecipeLibrary.blankRecipe(),
    )
        private set
    var dose: Double by mutableDoubleStateOf(recipe.dose)
    var waterTemp: Double by mutableDoubleStateOf(recipe.temperature)
    var grindValue: Double? by mutableStateOf(null)
    var grindText: String by mutableStateOf("")

    private val beanState = mutableStateOf(prefs.getString(KEY_BEAN, null))
    private val brewerState = mutableStateOf(prefs.getString(KEY_BREWER, null))
    private val grinderState = mutableStateOf(prefs.getString(KEY_GRINDER, null))
    private val filterState = mutableStateOf(prefs.getString(KEY_FILTER, null))

    var beanId: String?
        get() = beanState.value
        set(value) { beanState.value = value; save(KEY_BEAN, value) }
    var brewerId: String?
        get() = brewerState.value
        set(value) { brewerState.value = value; save(KEY_BREWER, value) }
    var grinderId: String?
        get() = grinderState.value
        set(value) { grinderState.value = value; save(KEY_GRINDER, value) }
    var filterId: String?
        get() = filterState.value
        set(value) { filterState.value = value; save(KEY_FILTER, value) }

    /** Bean + grinder for which the grind was set explicitly (setup assistant, "Brew again"). */
    private var pinnedGrindContext: String? = null

    private val grindContextKey: String get() = "${beanId ?: "-"}|${grinderId ?: "-"}"

    /** Sets the grind explicitly so a history recommendation doesn't replace it for the current bean + grinder. */
    fun pinGrind(value: Double?) {
        grindValue = value
        pinnedGrindContext = grindContextKey
    }

    val isGrindPinned: Boolean get() = pinnedGrindContext == grindContextKey

    val scaledRecipe: Recipe get() = recipe.scaled(dose)

    /** bean|grinder|recipe for which a history recommendation was last applied (emulates SwiftUI's onChange). */
    var lastRecommendationContext: String? = null

    private val knownGear = mutableMapOf<EquipmentType, Set<String>>()

    /** Clears selections of deleted gear and auto-selects newly added gear when nothing is selected. */
    fun reconcileGear(type: EquipmentType, ids: List<String>) {
        val previous = knownGear[type]
        val current = when (type) {
            EquipmentType.BREWER -> brewerId
            EquipmentType.GRINDER -> grinderId
            EquipmentType.FILTER -> filterId
            else -> return
        }
        var next = current
        if (next != null && next !in ids) next = null
        if (next == null && previous != null) next = ids.firstOrNull { it !in previous }
        if (next != current) {
            when (type) {
                EquipmentType.BREWER -> brewerId = next
                EquipmentType.GRINDER -> grinderId = next
                else -> filterId = next
            }
        }
        knownGear[type] = ids.toSet()
    }

    fun select(recipe: Recipe) {
        this.recipe = recipe
        dose = recipe.dose
        waterTemp = recipe.temperature
        prefs.edit().putString(KEY_RECIPE, recipe.id).apply()
    }

    /** Restores a custom recipe chosen last time (custom recipes live in the repository, not the presets). */
    fun restoreCustom(custom: List<Recipe>) {
        val id = prefs.getString(KEY_RECIPE, null) ?: return
        if (recipe.id == id) return
        custom.firstOrNull { it.id == id }?.let { select(it) }
    }

    private fun save(key: String, value: String?) {
        prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    }

    companion object {
        private const val KEY_RECIPE = "setup.recipeID"
        private const val KEY_BEAN = "setup.beanID"
        private const val KEY_BREWER = "setup.brewerID"
        private const val KEY_GRINDER = "setup.grinderID"
        private const val KEY_FILTER = "setup.filterID"
    }
}
