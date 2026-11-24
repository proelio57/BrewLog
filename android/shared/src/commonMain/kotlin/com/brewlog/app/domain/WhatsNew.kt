package com.brewlog.app.domain

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** The notes of the installed release (`whats-new.json`, written by CI from the release notes), and when to show them. */
@Serializable
data class WhatsNew(val version: String, val android: List<String> = emptyList()) {
    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun parse(text: String): WhatsNew? = runCatching { json.decodeFromString(serializer(), text) }.getOrNull()

        /**
         * The notes to show after an update, or null. Once per version, only when the release changed something on
         * Android, and not on a fresh install (onboarding not finished) or for notes of another version.
         */
        fun pending(notes: WhatsNew?, installedVersion: String, lastSeen: String?, onboardingDone: Boolean): WhatsNew? {
            if (notes == null || notes.version != installedVersion || lastSeen == installedVersion) return null
            if (!onboardingDone) return null
            return notes.takeIf { it.android.isNotEmpty() }
        }
    }
}
