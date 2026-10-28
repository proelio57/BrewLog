package com.brewlog.app.data

import com.brewlog.app.domain.AppData
import com.brewlog.app.domain.Bean
import com.brewlog.app.domain.BeanconquerorBackup
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.Equipment
import com.brewlog.app.domain.EquipmentPreset
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.domain.GrinderSpec
import com.brewlog.app.domain.InputLimits
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.RecipeFile
import com.brewlog.app.domain.newId
import com.brewlog.app.domain.sanitized
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement

/**
 * Imports files picked by the user: BrewLog recipe files and Beanconqueror backups.
 * Matches iOS DataImporter.swift.
 */
object DataImporter {
    data class Summary(
        var recipesAdded: Int = 0,
        var recipesUpdated: Int = 0,
        var beans: Int = 0,
        var brewers: Int = 0,
        var grinders: Int = 0,
        var brews: Int = 0,
        var skippedBrews: Int = 0,
    ) {
        val message: String
            get() {
                val parts = mutableListOf<String>()
                fun add(count: Int, singular: String, plural: String) {
                    if (count > 0) parts.add("$count ${if (count == 1) singular else plural}")
                }
                add(recipesAdded, "new recipe", "new recipes")
                add(recipesUpdated, "updated recipe", "updated recipes")
                add(brews, "brew", "brews")
                add(beans, "bean", "beans")
                add(grinders, "grinder", "grinders")
                add(brewers, "brewer", "brewers")
                var text = if (parts.isEmpty()) "Nothing new to import." else "Imported " + parts.joinToString(", ") + "."
                if (skippedBrews > 0) {
                    text += " $skippedBrews ${if (skippedBrews == 1) "brew was" else "brews were"} already in your journal."
                }
                return text
            }
    }

    const val MAX_FILE_SIZE = 200 * 1024 * 1024 // 200 MB
    private const val BEANCONQUEROR_PREFIX = "beanconqueror:"

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    @Throws(Exception::class)
    fun importData(data: ByteArray, repo: BrewRepository, presets: List<Recipe>): Summary {
        if (data.size > MAX_FILE_SIZE) throw IllegalArgumentException("This file is too large to import.")

        if (BeanconquerorBackup.isZip(data)) {
            val backup = BeanconquerorBackup.parse(data)
            return importBeanconqueror(backup, repo)
        }

        try {
            val element = json.parseToJsonElement(data.decodeToString())
            if (element is JsonObject) {
                if (BrewLogBackup.isWrapped(element)) return importBackup(BrewLogBackup.parse(element), repo, presets)
                if (BeanconquerorBackup.looksLikeBackup(element)) {
                    val backup = BeanconquerorBackup.parseJsonObject(element)
                    return importBeanconqueror(backup, repo)
                }
                if (element.containsKey("brews") || element.containsKey("beans") || element.containsKey("equipment")) {
                    val appData = json.decodeFromJsonElement<AppData>(element)
                    return importAppData(appData, repo, presets)
                }
            }
        } catch (_: Exception) {}

        val recipes = RecipeFile.decode(data)
        return importRecipes(recipes, repo, presets)
    }

    fun importRecipes(recipes: List<Recipe>, repo: BrewRepository, presets: List<Recipe>): Summary {
        val summary = Summary()
        repo.update { current ->
            var custom = current.customRecipes.toMutableList()
            val presetIds = presets.map { it.id }.toSet()

            for (recipe in recipes) {
                var item = recipe.copy(isCustom = true)
                if (item.id in presetIds) {
                    item = item.copy(id = "custom-${newId()}")
                }

                val existingIndex = custom.indexOfFirst { it.id == item.id }
                if (existingIndex >= 0) {
                    custom[existingIndex] = item
                    summary.recipesUpdated++
                } else {
                    custom.add(item)
                    summary.recipesAdded++
                }
            }
            current.copy(customRecipes = custom)
        }
        return summary
    }

    fun importBeanconqueror(backup: BeanconquerorBackup, repo: BrewRepository): Summary {
        val summary = Summary()
        val prefix = BEANCONQUEROR_PREFIX

        repo.update { current ->
            val existingGear = current.equipment.toMutableList()
            val existingBeans = current.beans.toMutableList()
            val existingBrews = current.brews.toMutableList()

            val importedBrewKeys = existingBrews.mapNotNull { it.externalId }.toSet()
            val gearByKey = mutableMapOf<String, Equipment>()
            for (item in existingGear) {
                item.externalId?.let { gearByKey[it] = item }
            }

            val beansByKey = mutableMapOf<String, Bean>()
            for (bean in existingBeans) {
                bean.externalId?.let { beansByKey[it] = bean }
            }

            fun existingGearItem(type: EquipmentType, name: String): Equipment? {
                return existingGear.firstOrNull { it.type == type && it.name.equals(name, ignoreCase = true) }
            }

            // Mills -> Grinders
            for (mill in backup.mills) {
                val key = prefix + mill.uuid
                val name = mill.name.sanitized(InputLimits.MAX_NAME_LENGTH)
                if (gearByKey.containsKey(key) || name.isEmpty()) continue

                val match = existingGearItem(EquipmentType.GRINDER, name)
                if (match != null) {
                    gearByKey[key] = match
                    continue
                }

                val preset = EquipmentPreset.grinders.firstOrNull {
                    name.contains(it.name, ignoreCase = true) || (name.length >= 4 && it.name.contains(name, ignoreCase = true))
                }
                val grinder = Equipment(
                    name = name,
                    type = EquipmentType.GRINDER,
                    grinder = preset?.grinder ?: GrinderSpec(),
                    notes = mill.note.sanitized(InputLimits.MAX_LONG_TEXT),
                    externalId = key,
                )
                existingGear.add(grinder)
                gearByKey[key] = grinder
                summary.grinders++
            }

            // Preparations -> Brewers
            val usedPreparations = backup.brews.map { it.preparationID }.toSet()
            for (prep in backup.preparations) {
                if (prep.finished && !usedPreparations.contains(prep.uuid)) continue
                val key = prefix + prep.uuid
                val name = prep.name.sanitized(InputLimits.MAX_NAME_LENGTH)
                if (gearByKey.containsKey(key) || name.isEmpty()) continue

                val match = existingGearItem(EquipmentType.BREWER, name)
                if (match != null) {
                    gearByKey[key] = match
                    continue
                }

                val brewer = Equipment(
                    name = name,
                    type = EquipmentType.BREWER,
                    method = BeanconquerorBackup.method(prep.type),
                    externalId = key,
                )
                existingGear.add(brewer)
                gearByKey[key] = brewer
                summary.brewers++
            }

            // Beans
            for (item in backup.beans) {
                val key = prefix + item.uuid
                if (beansByKey.containsKey(key)) continue
                val name = item.name.sanitized(InputLimits.MAX_NAME_LENGTH)
                val origin = listOf(item.country, item.region)
                    .map { it.sanitized(InputLimits.MAX_NAME_LENGTH) }
                    .filter { it.isNotEmpty() }
                    .joinToString(", ")

                val bagWeight = if (item.weight > 0) item.weight.coerceIn(1.0, InputLimits.MAX_BAG_WEIGHT) else 250.0
                val used = backup.brews.filter { it.beanID == item.uuid }.map { it.dose }.sum()
                val remaining = if (item.finished) 0.0 else maxOf(0.0, bagWeight - used.coerceIn(0.0, InputLimits.MAX_BAG_WEIGHT))

                val bean = Bean(
                    name = if (name.isEmpty()) "Imported beans" else name,
                    roaster = item.roaster.sanitized(InputLimits.MAX_NAME_LENGTH),
                    origin = origin,
                    varietal = item.variety.sanitized(InputLimits.MAX_NAME_LENGTH),
                    process = BeanconquerorBackup.process(item.processing) ?: com.brewlog.app.domain.ProcessMethod.WASHED,
                    roastLevel = BeanconquerorBackup.roastLevel(item.roast) ?: com.brewlog.app.domain.RoastLevel.LIGHT,
                    roastDate = item.roastingDate,
                    tastingNotes = item.aromatics.sanitized(InputLimits.MAX_SHORT_TEXT),
                    notes = item.note.sanitized(InputLimits.MAX_LONG_TEXT),
                    bagWeight = bagWeight,
                    remaining = remaining,
                    isArchived = item.finished,
                    createdAt = item.roastingDate ?: System.currentTimeMillis(),
                    externalId = key,
                )
                existingBeans.add(bean)
                beansByKey[key] = bean
                summary.beans++
            }

            // Brews
            for (item in backup.brews) {
                val key = prefix + item.uuid
                if (importedBrewKeys.contains(key)) {
                    summary.skippedBrews++
                    continue
                }

                val brewer = gearByKey[prefix + item.preparationID]
                val grinder = gearByKey[prefix + item.millID]
                val bean = beansByKey[prefix + item.beanID]
                val dose = item.dose.coerceIn(0.0, InputLimits.MAX_DOSE)
                val water = (if (item.water > 0) item.water else item.beverage).coerceIn(0.0, InputLimits.MAX_WATER)
                val grindValue = grinder?.let { BeanconquerorBackup.grindValue(item.grindSize) }

                val brew = Brew(
                    date = if (item.date > 0) item.date else System.currentTimeMillis(),
                    recipeId = "beanconqueror",
                    recipeName = brewer?.name ?: "Beanconqueror",
                    brewerId = brewer?.id,
                    brewerName = brewer?.name ?: "",
                    grinderId = grinder?.id,
                    grinderName = grinder?.name ?: "",
                    grinderSpec = grinder?.grinder,
                    dose = dose,
                    targetWater = water,
                    finalWeight = water,
                    totalTime = item.time.coerceIn(0.0, InputLimits.MAX_BREW_SECONDS),
                    waterTemp = item.temperature.coerceIn(0.0, 100.0),
                    grindSetting = item.grindSize.sanitized(InputLimits.MAX_SHORT_TEXT),
                    grindValue = grindValue,
                    beanId = bean?.id,
                    rating = backup.stars(item.rating),
                    notes = item.note.sanitized(InputLimits.MAX_LONG_TEXT),
                    externalId = key,
                )
                existingBrews.add(brew)
                summary.brews++
            }

            current.copy(equipment = existingGear, beans = existingBeans, brews = existingBrews)
        }

        return summary
    }

    /** The wrapped backup from iOS, web or Android: the data merged like [importAppData], plus the curves of the brews it adds. */
    fun importBackup(backup: BrewLogBackup, repo: BrewRepository, presets: List<Recipe>): Summary {
        val added = mutableSetOf<String>()
        val summary = importAppData(backup.data, repo, presets, added)
        for (id in added) {
            backup.samples[id]?.takeIf { it.isNotEmpty() }?.let { repo.importSamples(id, it) }
            backup.machine[id]?.takeIf { it.isNotEmpty() }?.let { repo.writeMachineSamples(id, it) }
        }
        // Nothing is replaced, but a photo a bean doesn't have yet is added.
        val beanIds = repo.data.value.beans.map { it.id }.toSet()
        for ((id, photo) in backup.photos) {
            if (id in beanIds && repo.beanPhoto(id) == null) repo.setBeanPhoto(id, photo)
        }
        return summary
    }

    fun importAppData(backup: AppData, repo: BrewRepository, presets: List<Recipe>, addedBrewIds: MutableSet<String>? = null): Summary {
        val summary = Summary()
        repo.update { current ->
            addedBrewIds?.clear()
            val existingBeanIds = current.beans.map { it.id }.toSet()
            val existingGearIds = current.equipment.map { it.id }.toSet()
            val existingBrewIds = current.brews.map { it.id }.toSet()
            val existingBrewKeys = current.brews.map { "${it.date}_${it.dose}_${it.targetWater}" }.toSet()

            val newBeans = current.beans.toMutableList()
            for (bean in backup.beans) {
                if (bean.id !in existingBeanIds) {
                    newBeans.add(bean)
                    summary.beans++
                }
            }

            val newGear = current.equipment.toMutableList()
            for (gear in backup.equipment) {
                if (gear.id !in existingGearIds) {
                    newGear.add(gear)
                    if (gear.type == EquipmentType.GRINDER) summary.grinders++ else summary.brewers++
                }
            }

            val newBrews = current.brews.toMutableList()
            for (brew in backup.brews) {
                val key = "${brew.date}_${brew.dose}_${brew.targetWater}"
                if (brew.id in existingBrewIds || key in existingBrewKeys) {
                    summary.skippedBrews++
                } else {
                    newBrews.add(brew)
                    addedBrewIds?.add(brew.id)
                    summary.brews++
                }
            }

            current.copy(beans = newBeans, equipment = newGear, brews = newBrews)
        }

        if (backup.customRecipes.isNotEmpty()) {
            val recipeSummary = importRecipes(backup.customRecipes, repo, presets)
            summary.recipesAdded += recipeSummary.recipesAdded
            summary.recipesUpdated += recipeSummary.recipesUpdated
        }

        return summary
    }

    /** Everything as one wrapped backup with weight and pressure curves, readable by iOS, web and Android. */
    fun exportBackup(repo: BrewRepository, exportedAt: java.time.Instant = java.time.Instant.now(), includePhotos: Boolean = true): String {
        val appData = repo.data.value
        val samples = appData.brews.associate { it.id to repo.samples(it.id) }.filterValues { it.isNotEmpty() }
        val machine = appData.brews.associate { it.id to repo.machineSamples(it.id) }.filterValues { it.isNotEmpty() }
        val photos = if (includePhotos) appData.beans.mapNotNull { b -> repo.beanPhoto(b.id)?.let { b.id to it } }.toMap() else emptyMap()
        return BrewLogBackup.encode(BrewLogBackup(appData, samples, machine, photos), exportedAt)
    }
}
