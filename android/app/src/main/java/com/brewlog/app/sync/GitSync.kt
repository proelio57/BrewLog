package com.brewlog.app.sync

import android.content.SharedPreferences
import com.brewlog.app.data.BrewRepository
import com.brewlog.app.data.DataImporter
import com.brewlog.app.domain.Recipe
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.time.Instant
import java.util.concurrent.TimeUnit

/**
 * Keeps the backup in a Git repository: downloads and merges what other devices pushed, then commits this
 * device's state when something changed. Port of GitSync.swift.
 */
class GitSync(
    private val prefs: SharedPreferences,
    private val secrets: SecretStore,
    private val repo: BrewRepository,
    private val presets: () -> List<Recipe>,
) {
    data class Status(val syncing: Boolean = false, val lastSync: Long? = null, val message: String? = null)

    private val json = Json { ignoreUnknownKeys = true }
    private val http = OkHttpClient.Builder().callTimeout(120, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS).build()

    private val _remote = MutableStateFlow(
        prefs.getString(KEY_REMOTE, null)?.let { runCatching { json.decodeFromString(GitRemote.serializer(), it) }.getOrNull() } ?: GitRemote(),
    )
    val remote: StateFlow<GitRemote> = _remote.asStateFlow()

    private val _status = MutableStateFlow(Status(lastSync = prefs.getLong(KEY_LAST_SYNC, 0L).takeIf { it > 0 }))
    val status: StateFlow<Status> = _status.asStateFlow()

    var autoSync: Boolean
        get() = prefs.getBoolean(KEY_AUTO, false)
        set(value) { prefs.edit().putBoolean(KEY_AUTO, value).apply() }

    val hasToken: Boolean get() = secrets.get(TOKEN) != null
    val isConfigured: Boolean get() = _remote.value.isValid && hasToken

    fun setRemote(remote: GitRemote) {
        _remote.value = remote
        prefs.edit().putString(KEY_REMOTE, json.encodeToString(GitRemote.serializer(), remote)).remove(KEY_SHA).remove(KEY_HASH).apply()
    }

    fun setToken(token: String?) {
        secrets.set(TOKEN, token)
        // A new token or repository starts fresh.
        prefs.edit().remove(KEY_SHA).remove(KEY_HASH).apply()
    }

    class SyncException(message: String) : Exception(message)

    /** After a brew, if turned on. At most every 2 minutes. */
    suspend fun syncIfEnabled() {
        if (!autoSync || !isConfigured || _status.value.syncing) return
        val last = _status.value.lastSync
        if (last != null && System.currentTimeMillis() - last < 120_000) return
        sync()
    }

    /** Download and merge, then commit this device's backup if it changed. */
    suspend fun sync(): Boolean {
        if (_status.value.syncing) return false
        _status.value = _status.value.copy(syncing = true)
        return try {
            var result = withContext(Dispatchers.IO) { syncOnce() }
            if (result == null) result = withContext(Dispatchers.IO) { syncOnce() } // the file changed in between: once more
            val now = System.currentTimeMillis()
            prefs.edit().putLong(KEY_LAST_SYNC, now).apply()
            _status.value = Status(false, now, result ?: "Someone else is writing to the file right now. Try again in a moment.")
            result != null
        } catch (e: Exception) {
            _status.value = _status.value.copy(syncing = false, message = e.message ?: "Sync failed.")
            false
        }
    }

    /** null when the write conflicted with a newer commit. */
    private fun syncOnce(): String? {
        val token = secrets.get(TOKEN)
        val remote = _remote.value
        if (token == null || !remote.isValid) throw SyncException("Set up the repository and token first.")

        // 1. What's in the repository? Merge it in (adds what's new, never deletes).
        val metadata = remote.metadataRequest(token) ?: throw SyncException("Set up the repository and token first.")
        var sha: String? = null
        var imported = 0
        val (metaCode, metaBody) = load(metadata, allow404 = true)
        if (metaCode != 404) {
            sha = GitRemote.blobSha(metaBody.decodeToString())
            if (sha != prefs.getString(KEY_SHA, null)) {
                val raw = remote.rawRequest(token) ?: throw SyncException("Set up the repository and token first.")
                val (_, file) = load(raw, allow404 = false)
                if (file.size > DataImporter.MAX_FILE_SIZE) throw SyncException(TOO_LARGE)
                val summary = DataImporter.importData(file, repo, presets())
                imported = summary.brews + summary.beans + summary.grinders + summary.brewers + summary.recipesAdded
            }
        }

        // 2. Commit this device's state if it changed since the last sync.
        val stable = DataImporter.exportBackup(repo, Instant.EPOCH, includePhotos = false).toByteArray()
        val hash = GitRemote.fnv1a(stable)
        if (sha != null && sha == prefs.getString(KEY_SHA, null) && hash == prefs.getString(KEY_HASH, null)) {
            return if (imported > 0) "Added $imported items from the repository." else "Up to date."
        }
        val content = DataImporter.exportBackup(repo, includePhotos = false).toByteArray()
        // The file APIs take files up to about 100 MB, base64 makes them a third larger.
        if (content.size > 70_000_000) throw SyncException(TOO_LARGE)
        val brews = repo.data.value.brews.size
        val message = "BrewLog backup: $brews brew" + if (brews == 1) "" else "s"
        val write = remote.writeRequest(content, sha, message, token) ?: throw SyncException("Set up the repository and token first.")
        val (writeCode, _) = load(write, allow404 = false, conflictIsNull = true)
        if (writeCode == 409 || writeCode == 422) return null

        // 3. Remember what was written, so the next sync knows whether anything changed.
        val (afterCode, after) = load(metadata, allow404 = true)
        if (afterCode == 200) {
            GitRemote.blobSha(after.decodeToString())?.let { prefs.edit().putString(KEY_SHA, it).putString(KEY_HASH, hash).apply() }
        }
        return if (imported > 0) "Added $imported items and saved the backup." else "Backup saved to ${remote.repository}."
    }

    private fun load(request: GitRemote.Request, allow404: Boolean, conflictIsNull: Boolean = false): Pair<Int, ByteArray> {
        val builder = Request.Builder().url(request.url)
        request.headers.forEach { (k, v) -> builder.header(k, v) }
        val body = request.body?.toRequestBody()
        builder.method(request.method, body ?: if (request.method == "GET") null else ByteArray(0).toRequestBody())
        http.newCall(builder.build()).execute().use { response ->
            val bytes = response.body?.bytes() ?: ByteArray(0)
            val code = response.code
            return when {
                code in 200..299 -> code to bytes
                code == 401 || code == 403 -> throw SyncException("The token was refused. Check that it may read and write this repository.")
                code == 404 && allow404 -> code to bytes
                code == 404 -> throw SyncException("Repository or branch not found (or the token can't see it).")
                (code == 409 || code == 422) && conflictIsNull -> code to bytes
                code == 413 -> throw SyncException(TOO_LARGE)
                else -> throw SyncException("Server error $code" + (GitRemote.errorMessage(bytes.decodeToString())?.let { ": $it" } ?: "."))
            }
        }
    }

    companion object {
        const val TOKEN = "git.token"
        private const val TOO_LARGE = "The backup is too large for the file API."
        private const val KEY_REMOTE = "git.remote"
        private const val KEY_AUTO = "git.auto"
        private const val KEY_LAST_SYNC = "git.lastSync"
        private const val KEY_SHA = "git.lastSHA"
        private const val KEY_HASH = "git.lastHash"
    }
}
