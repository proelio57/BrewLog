package com.brewlog.app

import com.brewlog.app.sync.GitRemote
import com.brewlog.app.sync.GitRemote.Provider
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Same scenarios as GitRemoteTests.swift: requests for GitHub, GitLab and Gitea, no network. */
class GitRemoteTest {
    private fun body(request: GitRemote.Request?): Map<String, String> =
        Json.parseToJsonElement(request!!.body!!).jsonObject.mapValues { it.value.jsonPrimitive.content }

    @Test fun gitHubRequests() {
        val remote = GitRemote(Provider.GITHUB, repository = "me/coffee", branch = "main", path = "brewlog/backup.json")
        assertNull(remote.problem)
        val meta = remote.metadataRequest("t0k")!!
        assertEquals("https://api.github.com/repos/me/coffee/contents/brewlog/backup.json?ref=main", meta.url)
        assertEquals("Bearer t0k", meta.headers["Authorization"])
        assertEquals("application/vnd.github.raw+json", remote.rawRequest("t")!!.headers["Accept"])

        val write = remote.writeRequest("{}".toByteArray(), "abc123", "BrewLog backup", "t")
        assertEquals("PUT", write!!.method)
        assertEquals(mapOf("content" to "e30=", "branch" to "main", "message" to "BrewLog backup", "sha" to "abc123"), body(write))
        assertTrue("sha" !in body(remote.writeRequest(ByteArray(0), null, "m", "t")))

        val enterprise = GitRemote(Provider.GITHUB, host = "git.corp.example", repository = "me/coffee")
        assertTrue(enterprise.metadataRequest("t")!!.url.startsWith("https://git.corp.example/api/v3/"))
    }

    @Test fun gitLabRequests() {
        val remote = GitRemote(Provider.GITLAB, repository = "group/sub/coffee", branch = "main", path = "brewlog/backup.json")
        assertNull(remote.problem)
        assertEquals("https://gitlab.com/api/v4/projects/group%2Fsub%2Fcoffee/repository/files/brewlog%2Fbackup.json?ref=main",
            remote.metadataRequest("t")!!.url)
        assertEquals("t", remote.metadataRequest("t")!!.headers["PRIVATE-TOKEN"])
        assertEquals("https://gitlab.com/api/v4/projects/group%2Fsub%2Fcoffee/repository/files/brewlog%2Fbackup.json/raw?ref=main",
            remote.rawRequest("t")!!.url)
        assertEquals("POST", remote.writeRequest(ByteArray(0), null, "m", "t")!!.method)
        val update = remote.writeRequest("x".toByteArray(), "0f0f", "m", "t")
        assertEquals("PUT", update!!.method)
        assertEquals(mapOf("content" to "eA==", "branch" to "main", "commit_message" to "m", "encoding" to "base64"), body(update))
    }

    @Test fun giteaRequests() {
        assertEquals("Gitea needs a server", GitRemote.Problem.HOST, GitRemote(Provider.GITEA, repository = "me/coffee").problem)
        val remote = GitRemote(Provider.GITEA, host = "git.home.lan:3000", repository = "me/coffee", path = "backup.json")
        assertNull(remote.problem)
        assertEquals("https://git.home.lan:3000/api/v1/repos/me/coffee/contents/backup.json?ref=main", remote.metadataRequest("t")!!.url)
        assertEquals("https://git.home.lan:3000/api/v1/repos/me/coffee/raw/backup.json?ref=main", remote.rawRequest("t")!!.url)
        assertEquals("token t", remote.metadataRequest("t")!!.headers["Authorization"])
        assertEquals("POST", remote.writeRequest(ByteArray(0), null, "m", "t")!!.method)
        assertEquals("PUT", remote.writeRequest(ByteArray(0), "ab", "m", "t")!!.method)
    }

    @Test fun rejectsUnsafeSettings() {
        fun problem(change: (GitRemote) -> GitRemote) = change(GitRemote(Provider.GITHUB, repository = "me/coffee")).problem
        assertEquals(GitRemote.Problem.REPOSITORY, problem { it.copy(repository = "me") })
        assertEquals(GitRemote.Problem.REPOSITORY, problem { it.copy(repository = "me/../x") })
        assertEquals("GitHub has no subgroups", GitRemote.Problem.REPOSITORY, problem { it.copy(repository = "a/b/c") })
        assertEquals(GitRemote.Problem.HOST, problem { it.copy(host = "https://evil.example/x") })
        assertEquals(GitRemote.Problem.HOST, problem { it.copy(host = "example.com:99999") })
        assertEquals(GitRemote.Problem.BRANCH, problem { it.copy(branch = "") })
        assertEquals(GitRemote.Problem.BRANCH, problem { it.copy(branch = "a..b") })
        assertEquals(GitRemote.Problem.PATH, problem { it.copy(path = "../backup.json") })
        assertEquals(GitRemote.Problem.PATH, problem { it.copy(path = "backup.txt") })
        assertEquals(GitRemote.Problem.PATH, problem { it.copy(path = "a b.json") })
        assertNull(problem { it.copy(branch = "feature/brewlog-1") })
        assertNull(GitRemote(Provider.GITEA, repository = "me/coffee").metadataRequest("t"))
    }

    @Test fun parsesResponses() {
        assertEquals("3a0f9c", GitRemote.blobSha("""{"sha": "3a0f9c", "size": 10}"""))
        assertEquals("beef01", GitRemote.blobSha("""{"blob_id": "beef01", "last_commit_id": "x"}"""))
        assertNull(GitRemote.blobSha("""{"sha": "not hex!"}"""))
        assertNull(GitRemote.blobSha("[]"))
        assertEquals("Bad credentials", GitRemote.errorMessage("""{"message": "Bad credentials"}"""))
        // Same hash as ContentHash.fnv1a on iOS.
        assertEquals("af63dc4c8601ec8c", GitRemote.fnv1a("a".toByteArray()))
        assertNotEquals(GitRemote.fnv1a("a".toByteArray()), GitRemote.fnv1a("b".toByteArray()))
    }
}
