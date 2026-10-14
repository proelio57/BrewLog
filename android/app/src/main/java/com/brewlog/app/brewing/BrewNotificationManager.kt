package com.brewlog.app.brewing

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.brewlog.app.BrewConfig
import com.brewlog.app.MainActivity
import com.brewlog.app.domain.mmss

/**
 * Ongoing notification for active brew sessions.
 * Equivalent to iOS BrewLiveActivity (Lock Screen timer and Dynamic Island).
 */
object BrewNotificationManager {
    private const val CHANNEL_ID = "brew_session"
    private const val NOTIFICATION_ID = 1001

    fun show(context: Context, config: BrewConfig, snapshot: BrewSnapshot) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Brew Assistant",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows live timer, step and weight while brewing"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val currentStep = snapshot.currentStepIndex?.let { config.recipe.steps.getOrNull(it) }
        val stepTitle = currentStep?.headline ?: "Brewing"
        val weightText = if (snapshot.usesScale) " · ${(if (snapshot.phase == BrewPhase.PREPARING) snapshot.weight else maxOf(snapshot.weight, 0.0)).toInt()} g" else ""
        val content = "${snapshot.elapsed.mmss()} · $stepTitle$weightText"

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(config.recipe.name)
            .setContentText(content)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()

        try {
            manager.notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Notification permission might be withheld on Android 13+
        }
    }

    fun dismiss(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        manager.cancel(NOTIFICATION_ID)
    }
}
