package com.brewlog.app.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.brewlog.app.brewing.BrewCue
import com.brewlog.app.domain.AppSettings
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.sin

/**
 * Synthesizes soft bell-like cues at runtime (no audio assets). Same synthesis as SoundPlayer.swift:
 * a fundamental with quickly decaying partials, a soft attack and an exponential decay.
 */
class SoundPlayer(private val settings: () -> AppSettings) {
    private data class Note(val frequency: Double, val delay: Double, val gain: Double)

    private val sampleRate = 44_100
    private val main = Handler(Looper.getMainLooper())

    private val buffers: Map<BrewCue, ShortArray> by lazy {
        mapOf(
            // E6: single, short, soft ping
            BrewCue.TARGET to render(listOf(Note(1318.5, 0.0, 0.9)), decay = 9.0, duration = 0.55),
            // A5 → E6 rising chime
            BrewCue.NEXT_STEP to render(listOf(Note(880.0, 0.0, 0.8), Note(1318.5, 0.13, 0.7)), decay = 5.0, duration = 1.3),
            // C6 → G5 → E5 calm, descending
            BrewCue.FINISH to render(
                listOf(Note(1046.5, 0.0, 0.7), Note(784.0, 0.2, 0.7), Note(659.3, 0.4, 0.8)), decay = 3.5, duration = 2.0,
            ),
            BrewCue.TICK to render(listOf(Note(1760.0, 0.0, 0.35)), decay = 35.0, duration = 0.12),
        )
    }

    fun play(cue: BrewCue) {
        val s = settings()
        if (!s.soundEnabled) return
        val pcm = buffers.getValue(cue)
        // Media plays even when the ringer is silent; sonification follows the ringer.
        val usage = if (s.silentModeSound) AudioAttributes.USAGE_MEDIA else AudioAttributes.USAGE_ASSISTANCE_SONIFICATION
        val track = try {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder().setUsage(usage).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(pcm.size * 2)
                .build()
        } catch (e: Exception) {
            return
        }
        track.write(pcm, 0, pcm.size)
        track.setVolume(s.soundVolume.toFloat())
        track.play()
        main.postDelayed({ track.release() }, pcm.size * 1000L / sampleRate + 300)
    }

    private fun render(notes: List<Note>, decay: Double, duration: Double): ShortArray {
        val frames = (duration * sampleRate).toInt()
        val fadeOut = (0.03 * sampleRate).toInt()
        return ShortArray(frames) { i ->
            val t = i.toDouble() / sampleRate
            var sample = 0.0
            for (note in notes) {
                if (t < note.delay) continue
                val lt = t - note.delay
                val envelope = min(1.0, lt / 0.008) * exp(-lt * decay)
                val w = 2 * PI * note.frequency * lt
                val partials = sin(w) +
                    0.30 * exp(-lt * decay * 0.8) * sin(2 * w) +
                    0.10 * exp(-lt * decay * 1.6) * sin(3.01 * w)
                sample += note.gain * envelope * partials
            }
            var value = sample * 0.32
            val remaining = frames - i
            if (remaining < fadeOut) value *= remaining.toDouble() / fadeOut
            (value.coerceIn(-1.0, 1.0) * Short.MAX_VALUE).toInt().toShort()
        }
    }
}

class Haptics(context: Context, private val settings: () -> AppSettings) {
    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    fun play(cue: BrewCue) {
        val v = vibrator ?: return
        if (!settings().hapticsEnabled || !v.hasVibrator()) return
        val effect = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            when (cue) {
                BrewCue.TARGET, BrewCue.TICK -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK)
                BrewCue.NEXT_STEP, BrewCue.FINISH -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_DOUBLE_CLICK)
            }
        } else {
            VibrationEffect.createOneShot(if (cue == BrewCue.TARGET || cue == BrewCue.TICK) 20L else 60L, VibrationEffect.DEFAULT_AMPLITUDE)
        }
        v.vibrate(effect)
    }

    fun tap() {
        val v = vibrator ?: return
        if (!settings().hapticsEnabled || !v.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            v.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
        }
    }
}
