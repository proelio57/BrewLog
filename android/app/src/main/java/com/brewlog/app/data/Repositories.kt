package com.brewlog.app.data

import android.content.SharedPreferences
import android.util.Log
import com.brewlog.app.BuildConfig
import com.brewlog.app.domain.AppData
import com.brewlog.app.domain.AppSettings
import com.brewlog.app.domain.Bean
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.Equipment
import com.brewlog.app.domain.MachineSample
import com.brewlog.app.domain.PingLeadMode
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.WeightSample
import com.brewlog.app.domain.validated
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.io.File
import kotlin.math.max

/** User settings in SharedPreferences (app-private storage). Mirrors App/Settings.swift. */
class SettingsRepository(private val prefs: SharedPreferences) {
    private val _settings = MutableStateFlow(load())
    val settings: StateFlow<AppSettings> = _settings.asStateFlow()
    val current: AppSettings get() = _settings.value

    fun update(transform: (AppSettings) -> AppSettings) {
        val next = transform(_settings.value)
        _settings.value = next
        prefs.edit()
            .putFloat("autoStartThreshold", next.autoStartThreshold.toFloat())
            .putString("pingLeadMode", next.pingLeadMode.raw)
            .putFloat("pingLeadGrams", next.pingLeadGrams.toFloat())
            .putFloat("reactionTime", next.reactionTime.toFloat())
            .putBoolean("soundEnabled", next.soundEnabled)
            .putBoolean("hapticsEnabled", next.hapticsEnabled)
            .putFloat("soundVolume", next.soundVolume.toFloat())
            .putBoolean("silentModeSound", next.silentModeSound)
            .putBoolean("countdownTicks", next.countdownTicks)
            .putBoolean("weighBeansFirst", next.weighBeansFirst)
            .putBoolean("valveCountdown", next.valveCountdown)
            .putBoolean("voicePrompts", next.voicePrompts)
            .putBoolean("voicePreview", next.voicePreview)
            .putString("recipeFilter", next.recipeFilter)
            .putBoolean("finishPing", next.finishPing)
            .putBoolean("keepAwake", next.keepAwake)
            .putBoolean("onboardingDone", next.onboardingDone)
            .putBoolean("setupBannerDismissed", next.setupBannerDismissed)
            .putBoolean("quickWeighAutoStart", next.quickWeighAutoStart)
            .putBoolean("chartShowsFlow", next.chartShowsFlow)
            .putBoolean("onlineRecipes", next.onlineRecipes)
            .putBoolean("espressoPressureEnabled", next.espressoPressureEnabled)
            .apply()
    }

    private fun load(): AppSettings {
        val d = AppSettings()
        return AppSettings(
            autoStartThreshold = prefs.getFloat("autoStartThreshold", d.autoStartThreshold.toFloat()).toDouble().coerceIn(0.5, 5.0),
            pingLeadMode = PingLeadMode.entries.firstOrNull { it.raw == prefs.getString("pingLeadMode", null) } ?: d.pingLeadMode,
            pingLeadGrams = prefs.getFloat("pingLeadGrams", d.pingLeadGrams.toFloat()).toDouble().coerceIn(0.0, 15.0),
            reactionTime = prefs.getFloat("reactionTime", d.reactionTime.toFloat()).toDouble().coerceIn(0.2, 1.5),
            soundEnabled = prefs.getBoolean("soundEnabled", d.soundEnabled),
            hapticsEnabled = prefs.getBoolean("hapticsEnabled", d.hapticsEnabled),
            soundVolume = prefs.getFloat("soundVolume", d.soundVolume.toFloat()).toDouble().coerceIn(0.1, 1.0),
            silentModeSound = prefs.getBoolean("silentModeSound", d.silentModeSound),
            countdownTicks = prefs.getBoolean("countdownTicks", d.countdownTicks),
            weighBeansFirst = prefs.getBoolean("weighBeansFirst", d.weighBeansFirst),
            valveCountdown = prefs.getBoolean("valveCountdown", d.valveCountdown),
            voicePrompts = prefs.getBoolean("voicePrompts", d.voicePrompts),
            voicePreview = prefs.getBoolean("voicePreview", d.voicePreview),
            recipeFilter = prefs.getString("recipeFilter", d.recipeFilter) ?: "",
            finishPing = prefs.getBoolean("finishPing", d.finishPing),
            keepAwake = prefs.getBoolean("keepAwake", d.keepAwake),
            onboardingDone = prefs.getBoolean("onboardingDone", d.onboardingDone),
            setupBannerDismissed = prefs.getBoolean("setupBannerDismissed", d.setupBannerDismissed),
            quickWeighAutoStart = prefs.getBoolean("quickWeighAutoStart", d.quickWeighAutoStart),
            chartShowsFlow = prefs.getBoolean("chartShowsFlow", d.chartShowsFlow),
            onlineRecipes = prefs.getBoolean("onlineRecipes", d.onlineRecipes),
            espressoPressureEnabled = prefs.getBoolean("espressoPressureEnabled", d.espressoPressureEnabled),
        )
    }
}

/**
 * All app data in one JSON file in app-private storage, written atomically (temp file + rename).
 * Weight curves are stored in one small file per brew so the main file stays small.
 */
class BrewRepository(private val directory: File, private val scope: CoroutineScope) {
    private val json = Json { ignoreUnknownKeys = true }
    private val dataFile = File(directory, "brewlog.json")
    private val samplesDir = File(directory, "samples").apply { mkdirs() }
    /** Espresso: pressure/temperature/flow curve per brew. */
    private val machineDir = File(directory, "machine").apply { mkdirs() }
    /** Bean photos as downsampled JPEG, one file per bean. */
    private val photosDir = File(directory, "beans").apply { mkdirs() }
    private val photoCache = mutableMapOf<String, ByteArray?>()
    private val _photoVersion = MutableStateFlow(0)
    /** Bumped whenever a photo changes, so screens reload thumbnails. */
    val photoVersion: StateFlow<Int> = _photoVersion.asStateFlow()
    private val writeLock = Mutex()
    private val samplesCache = mutableMapOf<String, List<WeightSample>>()
    private val machineCache = mutableMapOf<String, List<MachineSample>>()

    private val _data = MutableStateFlow(load())
    val data: StateFlow<AppData> = _data.asStateFlow()

    private fun load(): AppData {
        if (!dataFile.exists()) return AppData()
        return try {
            val loaded = json.decodeFromString(AppData.serializer(), dataFile.readText())
            // Stored data is re-validated before use.
            loaded.copy(customRecipes = loaded.customRecipes.map { it.validated() })
        } catch (e: Exception) {
            // Keep the unreadable file instead of overwriting it, so nothing is lost.
            dataFile.renameTo(File(directory, "brewlog.corrupt-${System.currentTimeMillis()}.json"))
            if (BuildConfig.DEBUG) Log.w("BrewRepository", "Could not read data file", e)
            AppData()
        }
    }

    fun update(transform: (AppData) -> AppData) {
        _data.update(transform)
        persist()
    }

    private fun persist() {
        scope.launch(Dispatchers.IO) {
            writeLock.withLock {
                // Always write the latest state, even if writes were queued out of order.
                val text = json.encodeToString(AppData.serializer(), _data.value)
                val temp = File(directory, "brewlog.json.tmp")
                temp.writeText(text)
                if (!temp.renameTo(dataFile)) {
                    dataFile.delete()
                    temp.renameTo(dataFile)
                }
            }
        }
    }

    // Brews

    fun saveNewBrew(brew: Brew, samples: List<WeightSample>, machineSamples: List<MachineSample> = emptyList()) {
        writeSamples(brew.id, samples)
        if (machineSamples.isNotEmpty()) writeMachineSamples(brew.id, machineSamples)
        update { d ->
            val beans = if (brew.beanId != null) d.beans.map {
                if (it.id == brew.beanId) it.copy(remaining = max(0.0, it.remaining - brew.dose)) else it
            } else d.beans
            d.copy(brews = d.brews + brew, beans = beans)
        }
    }

    fun updateBrew(id: String, transform: (Brew) -> Brew) = update { d ->
        d.copy(brews = d.brews.map { if (it.id == id) transform(it) else it })
    }

    /** Re-assigns the beans of a brew and moves the dose between the bags. */
    fun assignBean(brewId: String, beanId: String?) = update { d ->
        val brew = d.brews.firstOrNull { it.id == brewId } ?: return@update d
        if (brew.beanId == beanId) return@update d
        val beans = d.beans.map { bean ->
            when (bean.id) {
                brew.beanId -> bean.copy(remaining = bean.remaining + brew.dose)
                beanId -> bean.copy(remaining = max(0.0, bean.remaining - brew.dose))
                else -> bean
            }
        }
        d.copy(beans = beans, brews = d.brews.map { if (it.id == brewId) it.copy(beanId = beanId) else it })
    }

    fun deleteBrew(id: String) {
        update { d -> d.copy(brews = d.brews.filterNot { it.id == id }) }
        synchronized(samplesCache) { samplesCache.remove(id) }
        synchronized(machineCache) { machineCache.remove(id) }
        scope.launch(Dispatchers.IO) {
            sampleFile(id)?.delete()
            machineFile(id)?.delete()
        }
    }

    /** Espresso: the machine/pressure curve of a brew (empty for most brews). */
    fun machineSamples(brewId: String): List<MachineSample> {
        synchronized(machineCache) { machineCache[brewId]?.let { return it } }
        val file = machineFile(brewId) ?: return emptyList()
        val loaded = try {
            if (file.exists()) json.decodeFromString(ListSerializer(MachineSample.serializer()), file.readText()) else emptyList()
        } catch (e: Exception) {
            emptyList()
        }
        synchronized(machineCache) { machineCache[brewId] = loaded }
        return loaded
    }

    fun writeMachineSamples(brewId: String, samples: List<MachineSample>) {
        val file = machineFile(brewId) ?: return
        synchronized(machineCache) { machineCache[brewId] = samples }
        scope.launch(Dispatchers.IO) {
            file.writeText(json.encodeToString(ListSerializer(MachineSample.serializer()), samples))
        }
    }

    /** Stores an imported weight curve (backups). */
    fun importSamples(brewId: String, samples: List<WeightSample>) = writeSamples(brewId, samples)

    private fun machineFile(brewId: String): File? =
        if (brewId.matches(Regex("[A-Za-z0-9-]{1,64}"))) File(machineDir, "$brewId.json") else null

    fun samples(brewId: String): List<WeightSample> {
        synchronized(samplesCache) { samplesCache[brewId]?.let { return it } }
        val file = sampleFile(brewId) ?: return emptyList()
        val loaded = try {
            if (file.exists()) json.decodeFromString(ListSerializer(WeightSample.serializer()), file.readText()) else emptyList()
        } catch (e: Exception) {
            emptyList()
        }
        synchronized(samplesCache) { samplesCache[brewId] = loaded }
        return loaded
    }

    private fun writeSamples(brewId: String, samples: List<WeightSample>) {
        synchronized(samplesCache) { samplesCache[brewId] = samples }
        val file = sampleFile(brewId) ?: return
        scope.launch(Dispatchers.IO) {
            file.writeText(json.encodeToString(ListSerializer(WeightSample.serializer()), samples))
        }
    }

    /** Only accepts our own UUID-style ids, so a crafted id can never point outside the samples folder. */
    private fun sampleFile(brewId: String): File? =
        if (brewId.matches(Regex("[A-Za-z0-9-]{1,64}"))) File(samplesDir, "$brewId.json") else null

    // Beans, gear, recipes

    fun upsertBean(bean: Bean) = update { d ->
        d.copy(beans = if (d.beans.any { it.id == bean.id }) d.beans.map { if (it.id == bean.id) bean else it } else d.beans + bean)
    }

    fun deleteBean(id: String) {
        update { d ->
            d.copy(beans = d.beans.filterNot { it.id == id }, brews = d.brews.map { if (it.beanId == id) it.copy(beanId = null) else it })
        }
        setBeanPhoto(id, null)
    }

    /** The bean's photo (JPEG or PNG bytes), null when it has none. */
    fun beanPhoto(beanId: String): ByteArray? {
        synchronized(photoCache) { if (photoCache.containsKey(beanId)) return photoCache[beanId] }
        val file = photoFile(beanId)
        val loaded = if (file != null && file.exists()) runCatching { file.readBytes() }.getOrNull() else null
        synchronized(photoCache) { photoCache[beanId] = loaded }
        return loaded
    }

    fun setBeanPhoto(beanId: String, bytes: ByteArray?) {
        val file = photoFile(beanId) ?: return
        val clean = bytes?.takeIf { BrewLogBackup.isPhoto(it) }
        synchronized(photoCache) { photoCache[beanId] = clean }
        _photoVersion.value++
        scope.launch(Dispatchers.IO) {
            if (clean == null) file.delete() else file.writeBytes(clean)
        }
    }

    private fun photoFile(beanId: String): File? =
        if (beanId.matches(Regex("[A-Za-z0-9-]{1,64}"))) File(photosDir, "$beanId.jpg") else null

    fun upsertEquipment(item: Equipment) = update { d ->
        d.copy(equipment = if (d.equipment.any { it.id == item.id }) d.equipment.map { if (it.id == item.id) item else it } else d.equipment + item)
    }

    fun deleteEquipment(id: String) = update { d -> d.copy(equipment = d.equipment.filterNot { it.id == id }) }

    fun upsertRecipe(recipe: Recipe) = update { d ->
        val clean = recipe.validated().copy(isCustom = true)
        d.copy(customRecipes = if (d.customRecipes.any { it.id == clean.id }) d.customRecipes.map { if (it.id == clean.id) clean else it } else d.customRecipes + clean)
    }

    fun deleteRecipe(id: String) = update { d -> d.copy(customRecipes = d.customRecipes.filterNot { it.id == id }) }
}
