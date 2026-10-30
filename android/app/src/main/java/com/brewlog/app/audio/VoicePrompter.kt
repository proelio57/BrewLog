package com.brewlog.app.audio

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import com.brewlog.app.domain.AppSettings
import java.util.Locale

/** Reads the brew steps out loud with the system text-to-speech engine (on the device). Port of VoicePrompter.swift. */
class VoicePrompter(context: Context, private val settings: () -> AppSettings) {
    private var ready = false
    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        ready = status == TextToSpeech.SUCCESS
        // The prompts are English, so use an English voice.
        if (ready) tts.language = Locale.getDefault().takeIf { it.language == "en" } ?: Locale.US
    }

    /** Speaks right away, replacing anything still being said. [force] ignores the setting (test button). */
    fun say(text: String, force: Boolean = false) {
        if (!ready || (!force && !settings().voicePrompts)) return
        val params = Bundle().apply { putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, settings().soundVolume.toFloat()) }
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, params, "brewlog")
    }

    fun stop() {
        if (ready) tts.stop()
    }
}
