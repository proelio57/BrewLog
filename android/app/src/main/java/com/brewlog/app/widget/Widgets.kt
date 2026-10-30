package com.brewlog.app.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.brewlog.app.MainActivity
import com.brewlog.app.domain.AppData
import com.brewlog.app.domain.WidgetSnapshot
import kotlinx.serialization.json.Json

/** Keeps the widgets up to date: the app writes a small snapshot, the widgets only read it. Port of WidgetSync.swift. */
object WidgetSync {
    private const val PREFS = "brewlog.widgets"
    private const val KEY = "snapshot"
    private val json = Json { ignoreUnknownKeys = true }

    fun load(context: Context): WidgetSnapshot? = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getString(KEY, null)?.let { runCatching { json.decodeFromString(WidgetSnapshot.serializer(), it) }.getOrNull() }

    /** After a brew is saved, beans change or the app goes to the background. Only redraws when something changed. */
    suspend fun update(context: Context, data: AppData, selectedBeanId: String?) {
        val snapshot = WidgetSnapshot.from(data, selectedBeanId)
        if (snapshot == load(context)) return
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY, json.encodeToString(WidgetSnapshot.serializer(), snapshot)).apply()
        runCatching {
            StatusWidget().updateAll(context)
        }
    }

    /** Opens the app at brewlog://brew, …/weigh, …/journal or …/beans. */
    fun link(context: Context, target: String): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse("brewlog://$target"), context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
}

/** "Beans & last brew": current beans (days off roast, grams left) and the last brew. */
class StatusWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = WidgetSync.load(context)
        provideContent { GlanceTheme { StatusContent(context, snapshot) } }
    }
}

class StatusWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = StatusWidget()
}

@androidx.compose.runtime.Composable
private fun StatusContent(context: Context, snapshot: WidgetSnapshot?) {
    val colors = GlanceTheme.colors
    Column(
        GlanceModifier.fillMaxSize().background(colors.widgetBackground).cornerRadius(20.dp).padding(14.dp)
            .clickable(actionStartActivity(WidgetSync.link(context, "beans"))),
    ) {
        val bean = snapshot?.bean
        if (bean == null) {
            Text("BrewLog", style = TextStyle(fontWeight = FontWeight.Bold, color = colors.onSurface))
            Text(if (snapshot == null) "Open BrewLog once to see your beans and last brew here." else "No beans selected.",
                style = TextStyle(fontSize = 12.sp, color = colors.onSurfaceVariant))
        } else {
            Text(bean.name, maxLines = 1, style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 15.sp, color = colors.onSurface))
            val details = listOfNotNull(bean.daysOffRoast()?.let { "$it d off roast" }, "${bean.remaining.toInt()} g left")
            Text(details.joinToString(" · "), style = TextStyle(fontSize = 12.sp, color = colors.onSurfaceVariant))
            Spacer(GlanceModifier.height(6.dp))
            LinearProgressIndicator(bean.fraction.toFloat(), GlanceModifier.fillMaxWidth(), color = colors.primary, backgroundColor = colors.surfaceVariant)
        }
        Spacer(GlanceModifier.height(10.dp))
        val brew = snapshot?.lastBrew
        if (brew != null) {
            Text(brew.recipeName, maxLines = 1, style = TextStyle(fontWeight = FontWeight.Medium, fontSize = 13.sp, color = colors.onSurface))
            val stars = if (brew.rating > 0) "★".repeat(brew.rating.coerceAtMost(5)) + " · " else ""
            Text(stars + listOf(WidgetSnapshot.relative(brew.date), brew.grind).filter { it.isNotEmpty() }.joinToString(" · "),
                maxLines = 1, style = TextStyle(fontSize = 12.sp, color = colors.onSurfaceVariant))
        } else if (snapshot != null) {
            Text("No brews yet.", style = TextStyle(fontSize = 12.sp, color = colors.onSurfaceVariant))
        }
    }
}

/** "Quick start": Brew and Weigh buttons. */
class QuickWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                val colors = GlanceTheme.colors
                Row(
                    GlanceModifier.fillMaxSize().background(colors.widgetBackground).cornerRadius(20.dp).padding(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    QuickButton(context, "Brew", "brew", GlanceModifier.defaultWeight())
                    Spacer(GlanceModifier.width(8.dp))
                    QuickButton(context, "Weigh", "weigh", GlanceModifier.defaultWeight())
                }
            }
        }
    }
}

class QuickWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = QuickWidget()
}

@androidx.compose.runtime.Composable
private fun QuickButton(context: Context, title: String, target: String, modifier: GlanceModifier) {
    val colors = GlanceTheme.colors
    Box(
        modifier.background(colors.primaryContainer).cornerRadius(14.dp).padding(vertical = 14.dp)
            .clickable(actionStartActivity(WidgetSync.link(context, target))),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 15.sp, color = colors.onPrimaryContainer))
    }
}
