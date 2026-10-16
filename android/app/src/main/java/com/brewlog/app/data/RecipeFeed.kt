package com.brewlog.app.data

import android.content.SharedPreferences
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.RecipeFile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Online recipe updates: downloads recipes.json from the repository's recipe feed.
 * Matches iOS RecipeFeed.swift: merges remote presets, updates offline cache, and respects user settings.
 */
class RecipeFeed(
    private val bundledRecipes: List<Recipe>,
    private val cacheDirectory: File,
    private val prefs: SharedPreferences,
    private val isEnabled: () -> Boolean,
    private val scope: CoroutineScope,
    private val feedUrlString: String = DEFAULT_FEED_URL,
) {
    private val cacheFile = File(cacheDirectory, "recipes-feed.json")

    private val _presets = MutableStateFlow(loadInitial())
    val presets: StateFlow<List<Recipe>> = _presets.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    var lastSync: Long?
        get() {
            val v = prefs.getLong(PREF_LAST_SYNC, 0L)
            return if (v > 0) v else null
        }
        private set(value) {
            prefs.edit().putLong(PREF_LAST_SYNC, value ?: 0L).apply()
        }

    private fun loadInitial(): List<Recipe> {
        val cached = if (cacheFile.exists()) {
            try {
                RecipeFile.decode(cacheFile.readText())
            } catch (_: Exception) {
                emptyList()
            }
        } else {
            emptyList()
        }
        return merge(bundledRecipes, cached)
    }

    fun syncIfNeeded(force: Boolean = false) {
        if (!isEnabled() || feedUrlString.isEmpty() || _isSyncing.value) return
        val last = lastSync
        if (!force && last != null && (System.currentTimeMillis() - last) < CHECK_INTERVAL_MS) return

        scope.launch {
            _isSyncing.value = true
            _lastError.value = null
            try {
                val remote = withContext(Dispatchers.IO) { downloadFeed(feedUrlString) }
                try {
                    cacheFile.writeText(RecipeFile.encode(remote))
                } catch (_: Exception) {}
                _presets.value = merge(bundledRecipes, remote)
                lastSync = System.currentTimeMillis()
                _lastError.value = null
            } catch (e: Exception) {
                _lastError.value = e.localizedMessage ?: "Sync failed"
            } finally {
                _isSyncing.value = false
            }
        }
    }

    private fun downloadFeed(urlStr: String): List<Recipe> {
        val url = URL(urlStr)
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 20_000
            setRequestProperty("Accept", "application/json")
        }
        try {
            val code = conn.responseCode
            if (code != HttpURLConnection.HTTP_OK) {
                throw IllegalStateException("Server returned HTTP $code")
            }
            val bytes = conn.inputStream.use { it.readBytes() }
            if (bytes.size > MAX_DOWNLOAD_SIZE) {
                throw IllegalStateException("Feed file is too large (${bytes.size} bytes).")
            }
            return RecipeFile.decode(bytes)
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        const val CHECK_INTERVAL_MS = 6L * 3600L * 1000L // 6 hours
        const val MAX_DOWNLOAD_SIZE = 1024 * 1024 // 1 MB
        const val DEFAULT_FEED_URL = "https://raw.githubusercontent.com/proelio57/BrewLog/sidestore/recipes.json"
        private const val PREF_LAST_SYNC = "recipeFeed.lastSync"

        /**
         * Bundled recipes first (in their original order, replaced by remote versions if matching ID),
         * followed by new remote recipes (with isCustom = null).
         */
        fun merge(bundled: List<Recipe>, remote: List<Recipe>): List<Recipe> {
            val remoteById = mutableMapOf<String, Recipe>()
            for (r in remote) {
                if (r.id.isNotEmpty()) {
                    remoteById[r.id] = r.copy(isCustom = null)
                }
            }

            val bundledIds = bundled.map { it.id }.toSet()
            val seen = mutableSetOf<String>()
            val added = remote.mapNotNull { remoteById[it.id] }
                .filter { it.id !in bundledIds && seen.add(it.id) }

            return bundled.map { remoteById[it.id] ?: it } + added
        }
    }
}
