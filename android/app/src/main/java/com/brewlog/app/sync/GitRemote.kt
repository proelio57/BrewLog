package com.brewlog.app.sync

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.net.URLEncoder
import java.util.Base64

/**
 * Where the backup is kept in a Git repository: GitHub, GitLab or Gitea / Forgejo, written with their file APIs
 * (one commit per backup). Port of GitRemote.swift; requests are plain values so they can be tested without network.
 */
@Serializable
data class GitRemote(
    val provider: Provider = Provider.GITHUB,
    /** Empty = the provider's public host (github.com, gitlab.com). Required for Gitea. */
    val host: String = "",
    /** "owner/name"; GitLab also "group/subgroup/name". */
    val repository: String = "",
    val branch: String = "main",
    val path: String = "brewlog/backup.json",
) {
    @Serializable
    enum class Provider(val displayName: String, val defaultHost: String?) {
        GITHUB("GitHub", "github.com"),
        GITLAB("GitLab", "gitlab.com"),
        GITEA("Gitea / Forgejo", null),
    }

    enum class Problem(val message: String) {
        HOST("Enter the server, e.g. git.example.com."),
        REPOSITORY("Enter the repository as owner/name."),
        BRANCH("Enter a branch name, e.g. main."),
        PATH("Enter a file path ending in .json, e.g. brewlog/backup.json."),
    }

    /** An HTTP request as data. */
    data class Request(val method: String, val url: String, val headers: Map<String, String>, val body: String? = null)

    val effectiveHost: String?
        get() = host.trim().lowercase().ifEmpty { null } ?: provider.defaultHost

    val problem: Problem?
        get() {
            val h = effectiveHost
            if (h == null || !isHost(h)) return Problem.HOST
            val parts = repository.split("/")
            val maxParts = if (provider == Provider.GITLAB) 20 else 2
            if (parts.size < 2 || parts.size > maxParts || !parts.all(::isName)) return Problem.REPOSITORY
            if (branch.isEmpty() || branch.length > 100 || branch.contains("..") || branch.startsWith("/") || branch.endsWith("/") ||
                !branch.all { (it.isLetterOrDigit() || it in "-_./") && it.code < 128 }
            ) return Problem.BRANCH
            if (!path.lowercase().endsWith(".json") || path.length > 200 || !path.split("/").all(::isName)) return Problem.PATH
            return null
        }

    val isValid: Boolean get() = problem == null

    private val apiBase: String?
        get() {
            if (!isValid) return null
            val h = effectiveHost ?: return null
            return when (provider) {
                Provider.GITHUB -> if (h == "github.com") "https://api.github.com" else "https://$h/api/v3"
                Provider.GITLAB -> "https://$h/api/v4"
                Provider.GITEA -> "https://$h/api/v1"
            }
        }

    /** Path segments encoded one by one (GitHub, Gitea), or as a whole with "/" → %2F (GitLab). */
    private val encodedPath: String
        get() = if (provider == Provider.GITLAB) encode(path) else path.split("/").joinToString("/") { encode(it) }

    private val fileUrl: String?
        get() {
            val base = apiBase ?: return null
            return when (provider) {
                Provider.GITHUB, Provider.GITEA -> "$base/repos/$repository/contents/$encodedPath"
                Provider.GITLAB -> "$base/projects/${encode(repository)}/repository/files/$encodedPath"
            }
        }

    private fun withRef(url: String) = "$url?ref=${encode(branch)}"

    private fun headers(token: String, accept: String): Map<String, String> {
        val map = linkedMapOf<String, String>()
        when (provider) {
            Provider.GITHUB -> {
                map["Authorization"] = "Bearer $token"
                map["X-GitHub-Api-Version"] = "2022-11-28"
            }
            Provider.GITLAB -> map["PRIVATE-TOKEN"] = token
            Provider.GITEA -> map["Authorization"] = "token $token"
        }
        map["User-Agent"] = "BrewLog"
        map["Accept"] = accept
        map["Cache-Control"] = "no-cache"
        return map
    }

    /** File info with the blob sha, 404 when the file doesn't exist yet. */
    fun metadataRequest(token: String): Request? = fileUrl?.let { Request("GET", withRef(it), headers(token, "application/json")) }

    /** The file itself. */
    fun rawRequest(token: String): Request? {
        val base = fileUrl ?: return null
        val url = when (provider) {
            Provider.GITHUB -> withRef(base)
            Provider.GITLAB -> withRef("$base/raw")
            Provider.GITEA -> withRef("$apiBase/repos/$repository/raw/$encodedPath")
        }
        return Request("GET", url, headers(token, if (provider == Provider.GITHUB) "application/vnd.github.raw+json" else "*/*"))
    }

    /** Creates or updates the file as a new commit. [sha] is the current blob (null = create). */
    fun writeRequest(content: ByteArray, sha: String?, message: String, token: String): Request? {
        val url = fileUrl ?: return null
        val body = sortedMapOf("content" to Base64.getEncoder().encodeToString(content), "branch" to branch)
        val method = when (provider) {
            Provider.GITHUB -> {
                body["message"] = message
                sha?.let { body["sha"] = it }
                "PUT"
            }
            Provider.GITEA -> {
                body["message"] = message
                sha?.let { body["sha"] = it }
                if (sha == null) "POST" else "PUT"
            }
            Provider.GITLAB -> {
                body["commit_message"] = message
                body["encoding"] = "base64"
                if (sha == null) "POST" else "PUT"
            }
        }
        val json = buildJsonObject { body.forEach { (k, v) -> put(k, v) } }.toString()
        return Request(method, url, headers(token, "application/json") + ("Content-Type" to "application/json"), json)
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /** The blob sha from a metadata response (GitHub/Gitea `sha`, GitLab `blob_id`). */
        fun blobSha(text: String): String? {
            val obj = runCatching { json.parseToJsonElement(text) as? JsonObject }.getOrNull() ?: return null
            val value = ((obj["sha"] ?: obj["blob_id"]) as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
            return value.takeIf { it.isNotEmpty() && it.length <= 128 && it.all { c -> c.isDigit() || c.lowercaseChar() in 'a'..'f' } }
        }

        /** The server's error message, if it sent one. */
        fun errorMessage(text: String): String? {
            val obj = runCatching { json.parseToJsonElement(text) as? JsonObject }.getOrNull() ?: return null
            return ((obj["message"] ?: obj["error"]) as? JsonPrimitive)?.takeIf { it.isString }?.content?.take(200)
        }

        /** Change detection for the backup (stable across launches). */
        fun fnv1a(bytes: ByteArray): String {
            var hash = 0xcbf29ce484222325uL
            for (b in bytes) hash = (hash xor b.toUByte().toULong()) * 0x00000100000001b3uL
            return hash.toString(16)
        }

        private fun encode(text: String) = URLEncoder.encode(text, "UTF-8").replace("+", "%20")

        /** A host name or IP with an optional port, no scheme or path. */
        private fun isHost(host: String): Boolean {
            if (host.isEmpty() || host.length > 253 || host.startsWith(".") || host.startsWith("-")) return false
            val parts = host.split(":")
            if (parts.size > 2 || parts[0].isEmpty()) return false
            if (!parts[0].all { (it.isLetterOrDigit() || it == '.' || it == '-') && it.code < 128 }) return false
            return parts.size == 1 || parts[1].toIntOrNull()?.let { it in 1..65_535 } == true
        }

        /** One path segment: letters, digits, "-", "_", "." but not "." or "..". */
        private fun isName(part: String) = part.isNotEmpty() && part.length <= 100 && part != "." && part != ".." &&
            part.all { (it.isLetterOrDigit() || it in "-_.") && it.code < 128 }
    }
}
