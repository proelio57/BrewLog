package com.brewlog.app.sync

import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Secrets (Git token, Anthropic API key) encrypted with a key in the Android Keystore that never leaves the device,
 * stored as ciphertext in SharedPreferences. Android counterpart of the iOS Keychain helper.
 */
class SecretStore(private val prefs: SharedPreferences) {
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun key(): SecretKey {
        (keyStore.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    fun get(account: String): String? {
        val stored = prefs.getString(PREFIX + account, null) ?: return null
        return runCatching {
            val bytes = Base64.getDecoder().decode(stored)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, IV_LENGTH))
            String(cipher.doFinal(bytes, IV_LENGTH, bytes.size - IV_LENGTH), Charsets.UTF_8)
        }.getOrNull()
    }

    fun set(account: String, value: String?) {
        val trimmed = value?.trim()
        if (trimmed.isNullOrEmpty()) {
            prefs.edit().remove(PREFIX + account).apply()
            return
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.iv + cipher.doFinal(trimmed.toByteArray(Charsets.UTF_8))
        prefs.edit().putString(PREFIX + account, Base64.getEncoder().encodeToString(encrypted)).apply()
    }

    companion object {
        private const val ALIAS = "brewlog.secrets"
        private const val PREFIX = "secret."
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_LENGTH = 12
    }
}
