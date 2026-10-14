package com.brewlog.app.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.brewlog.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

data class UpdateInfo(
    val tagName: String,
    val versionName: String,
    val title: String,
    val notes: String,
    val apkUrl: String,
    val apkFileName: String,
    val apkSize: Long,
)

/**
 * Checks for app updates via GitHub Releases API and handles in-app APK installation.
 */
object AppUpdater {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val GITHUB_REPO: String = BuildConfig.RELEASE_REPO

    private val _updateState = MutableStateFlow<UpdateState>(UpdateState.Idle)
    val updateState: StateFlow<UpdateState> = _updateState.asStateFlow()

    sealed class UpdateState {
        object Idle : UpdateState()
        object Checking : UpdateState()
        data class Available(val info: UpdateInfo) : UpdateState()
        object UpToDate : UpdateState()
        data class Downloading(val progress: Float) : UpdateState()
        data class ReadyToInstall(val apkFile: File) : UpdateState()
        data class Error(val message: String) : UpdateState()
    }

    suspend fun checkForUpdates(currentVersion: String = BuildConfig.VERSION_NAME): UpdateInfo? = withContext(Dispatchers.IO) {
        _updateState.value = UpdateState.Checking
        try {
            val url = URL("https://api.github.com/repos/$GITHUB_REPO/releases/latest")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 10_000
                readTimeout = 15_000
                setRequestProperty("Accept", "application/vnd.github.v3+json")
                setRequestProperty("User-Agent", "BrewLog-Android")
            }

            val body = conn.inputStream.use { it.readBytes().decodeToString() }
            conn.disconnect()

            val root = json.parseToJsonElement(body).jsonObject
            val tag = root["tag_name"]?.jsonPrimitive?.content.orEmpty()
            val title = root["name"]?.jsonPrimitive?.content ?: tag
            val notes = root["body"]?.jsonPrimitive?.content.orEmpty()

            val remoteVersion = tag.removePrefix("v").removePrefix("V")
            val cleanCurrent = currentVersion.removePrefix("v").removePrefix("V")

            if (!isNewer(cleanCurrent, remoteVersion)) {
                _updateState.value = UpdateState.UpToDate
                return@withContext null
            }

            val assets = root["assets"]?.jsonArray ?: emptyList()
            var apkUrl = ""
            var apkName = "BrewLog-$remoteVersion.apk"
            var apkSize = 0L

            for (item in assets) {
                val obj = item.jsonObject
                val name = obj["name"]?.jsonPrimitive?.content.orEmpty()
                if (name.endsWith(".apk", ignoreCase = true)) {
                    apkUrl = obj["browser_download_url"]?.jsonPrimitive?.content.orEmpty()
                    apkName = name
                    apkSize = obj["size"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
                    break
                }
            }

            if (apkUrl.isEmpty()) {
                _updateState.value = UpdateState.UpToDate
                return@withContext null
            }

            val info = UpdateInfo(
                tagName = tag,
                versionName = remoteVersion,
                title = title,
                notes = notes,
                apkUrl = apkUrl,
                apkFileName = apkName,
                apkSize = apkSize,
            )
            _updateState.value = UpdateState.Available(info)
            info
        } catch (e: Exception) {
            _updateState.value = UpdateState.Error(e.localizedMessage ?: "Failed to check for updates")
            null
        }
    }

    suspend fun downloadAndInstall(context: Context, info: UpdateInfo) = withContext(Dispatchers.IO) {
        _updateState.value = UpdateState.Downloading(0f)
        try {
            val updateDir = File(context.cacheDir, "updates").apply { mkdirs() }
            val targetFile = File(updateDir, info.apkFileName)
            if (targetFile.exists()) targetFile.delete()

            val url = URL(info.apkUrl)
            val conn = (url.openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = true
                connectTimeout = 15_000
                readTimeout = 30_000
                setRequestProperty("User-Agent", "BrewLog-Android")
            }

            val totalBytes = conn.contentLengthLong.takeIf { it > 0 } ?: info.apkSize
            var downloaded = 0L

            conn.inputStream.use { input ->
                FileOutputStream(targetFile).use { output ->
                    val buffer = ByteArray(8 * 1024)
                    var read: Int
                    while (input.read(buffer).also { read = it } != -1) {
                        output.write(buffer, 0, read)
                        downloaded += read
                        if (totalBytes > 0) {
                            _updateState.value = UpdateState.Downloading(downloaded.toFloat() / totalBytes)
                        }
                    }
                }
            }
            conn.disconnect()

            _updateState.value = UpdateState.ReadyToInstall(targetFile)
            withContext(Dispatchers.Main) {
                installApk(context, targetFile)
            }
        } catch (e: Exception) {
            _updateState.value = UpdateState.Error(e.localizedMessage ?: "Download failed")
        }
    }

    fun installApk(context: Context, apkFile: File) {
        if (!apkFile.exists()) return

        // On Android 8.0+, check if unknown app sources are allowed
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!context.packageManager.canRequestPackageInstalls()) {
                val settingsIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(settingsIntent)
                return
            }
        }

        val apkUri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            apkFile,
        )

        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(installIntent)
    }

    /**
     * Compares two semantic version strings (e.g. "1.0.5" vs "1.0.4").
     * Returns true if target is strictly newer than current.
     */
    fun isNewer(current: String, target: String): Boolean {
        val currParts = current.split('.', '-').mapNotNull { it.toIntOrNull() }
        val targetParts = target.split('.', '-').mapNotNull { it.toIntOrNull() }

        val maxLen = maxOf(currParts.size, targetParts.size)
        for (i in 0 until maxLen) {
            val c = currParts.getOrElse(i) { 0 }
            val t = targetParts.getOrElse(i) { 0 }
            if (t > c) return true
            if (t < c) return false
        }
        return false
    }
}
