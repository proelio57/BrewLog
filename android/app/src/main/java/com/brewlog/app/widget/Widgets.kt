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
import java.util.Locale
import kotlin.math.roundToInt

/** Keeps the widgets up to date: the app writes a small snapshot, the widgets only read it. Port of WidgetSync.swift. */
object WidgetSync {
    private const val PREFS = "brewlog.widgets"
    private const val KEY = "snapshot"
    private val json = Json { ignoreUnknownKeys = true }

    fun load(context: Context): WidgetSnapshot? = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getString(KEY, null)?.let { runCatching { json.decodeFromString(WidgetSnapshot.serializer(), it) }.getOrNull() }

    /** After a brew is saved, beans change or the app goes to the background. Only redraws when something changed. */
    suspend fun update(
        context: Context,
        data: AppData,
        selectedBeanId: String?,
        setup: WidgetSnapshot.Setup? = null,
    ) {
        val snapshot = WidgetSnapshot.from(data, selectedBeanId, setup)
        if (snapshot == load(context)) return
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY, json.encodeToString(WidgetSnapshot.serializer(), snapshot)).apply()
        runCatching { StatusWidget().updateAll(context) }
        runCatching { QuickWidget().updateAll(context) }
        runCatching { StatsWidget().updateAll(context) }
        runCatching { BeansLeftWidget().updateAll(context) }
    }

    suspend fun update(context: Context, data: AppData, selectedBeanId: String?) {
        update(context, data, selectedBeanId, null)
    }

    /** Opens the app at brewlog://start, …/brew, …/weigh, …/journal or …/beans. */
    fun link(context: Context, target: String): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse("brewlog://$target"), context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
}

// MARK: - Next brew (Status widget)

/** "Next brew": current beans (days off roast, grams/cups left) and next brew recipe + grind. */
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
            .clickable(actionStartActivity(WidgetSync.link(context, "start"))),
    ) {
        Text("Next brew", style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 12.sp, color = colors.primary))
        Spacer(GlanceModifier.height(4.dp))
        val bean = snapshot?.bean
        if (bean == null) {
            Text("BrewLog", style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 15.sp, color = colors.onSurface))
            Text(
                if (snapshot == null) "Open BrewLog once to see your beans here." else "No beans selected.",
                style = TextStyle(fontSize = 12.sp, color = colors.onSurfaceVariant),
            )
        } else {
            Text(bean.name, maxLines = 1, style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 15.sp, color = colors.onSurface))
            val days = bean.daysOffRoast()?.let { "$it d off roast" }
            val amount = bean.cupsLeft?.let { if (it == 1) "≈ 1 cup left" else "≈ $it cups left" } ?: "${bean.remaining.toInt()} g left"
            val details = listOfNotNull(days, amount)
            Text(details.joinToString(" · "), style = TextStyle(fontSize = 12.sp, color = colors.onSurfaceVariant))
            Spacer(GlanceModifier.height(4.dp))
            LinearProgressIndicator(
                bean.fraction.toFloat(),
                GlanceModifier.fillMaxWidth(),
                color = colors.primary,
                backgroundColor = colors.surfaceVariant,
            )
        }
        Spacer(GlanceModifier.height(8.dp))
        val next = snapshot?.next
        val lastBrew = snapshot?.lastBrew
        if (next != null) {
            val parts = listOf(next.grind, next.recipeName).filter { it.isNotEmpty() }
            val label = if (parts.isNotEmpty()) "Next: " + parts.joinToString(" · ") else next.recipeName
            Text(label, maxLines = 1, style = TextStyle(fontWeight = FontWeight.Medium, fontSize = 12.sp, color = colors.onSurface))
        } else if (lastBrew != null) {
            Text(lastBrew.recipeName, maxLines = 1, style = TextStyle(fontWeight = FontWeight.Medium, fontSize = 12.sp, color = colors.onSurface))
            val stars = if (lastBrew.rating > 0) "★".repeat(lastBrew.rating.coerceAtMost(5)) + " · " else ""
            Text(
                stars + listOf(WidgetSnapshot.relative(lastBrew.date), lastBrew.grind).filter { it.isNotEmpty() }.joinToString(" · "),
                maxLines = 1,
                style = TextStyle(fontSize = 11.sp, color = colors.onSurfaceVariant),
            )
        } else if (snapshot != null) {
            Text("No brews yet.", style = TextStyle(fontSize = 12.sp, color = colors.onSurfaceVariant))
        }
    }
}

// MARK: - Quick start

/** "Quick start": Brew and Weigh buttons with dose/recipe caption. */
class QuickWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = WidgetSync.load(context)
        provideContent { GlanceTheme { QuickContent(context, snapshot) } }
    }
}

class QuickWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = QuickWidget()
}

@androidx.compose.runtime.Composable
private fun QuickContent(context: Context, snapshot: WidgetSnapshot?) {
    val colors = GlanceTheme.colors
    Column(
        GlanceModifier.fillMaxSize().background(colors.widgetBackground).cornerRadius(20.dp).padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            QuickButton(context, "Brew", "start", GlanceModifier.defaultWeight())
            Spacer(GlanceModifier.width(8.dp))
            QuickButton(context, "Weigh", "weigh", GlanceModifier.defaultWeight())
        }
        val setup = snapshot?.setup
        if (setup != null) {
            Spacer(GlanceModifier.height(4.dp))
            Text(
                "${setup.recipeName} · ${setup.dose.roundToInt()} g",
                maxLines = 1,
                style = TextStyle(fontSize = 11.sp, color = colors.onSurfaceVariant),
            )
        }
    }
}

@androidx.compose.runtime.Composable
private fun QuickButton(context: Context, title: String, target: String, modifier: GlanceModifier) {
    val colors = GlanceTheme.colors
    Box(
        modifier.background(colors.primaryContainer).cornerRadius(14.dp).padding(vertical = 12.dp)
            .clickable(actionStartActivity(WidgetSync.link(context, target))),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 15.sp, color = colors.onPrimaryContainer))
    }
}

// MARK: - Coffee stats

/** "Coffee stats": Brews this week, day bars, streak, and average rating. */
class StatsWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = WidgetSync.load(context)
        provideContent { GlanceTheme { StatsContent(context, snapshot) } }
    }
}

class StatsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = StatsWidget()
}

@androidx.compose.runtime.Composable
private fun StatsContent(context: Context, snapshot: WidgetSnapshot?) {
    val colors = GlanceTheme.colors
    val stats = snapshot?.stats()
    Column(
        GlanceModifier.fillMaxSize().background(colors.widgetBackground).cornerRadius(20.dp).padding(14.dp)
            .clickable(actionStartActivity(WidgetSync.link(context, "journal"))),
    ) {
        Text("This week", style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 12.sp, color = colors.primary))
        Spacer(GlanceModifier.height(2.dp))
        if (stats != null) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    "${stats.weekTotal}",
                    style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 26.sp, color = colors.onSurface),
                )
                Spacer(GlanceModifier.width(4.dp))
                Text(
                    if (stats.weekTotal == 1) "brew" else "brews",
                    style = TextStyle(fontSize = 12.sp, color = colors.onSurfaceVariant),
                )
            }
            Spacer(GlanceModifier.height(4.dp))
            DayBarsRow(stats.perDay, colors)
            Spacer(GlanceModifier.height(4.dp))
            val parts = listOfNotNull(
                if (stats.streak > 1) "🔥 ${stats.streak} days" else null,
                stats.averageRating?.let { "★ " + String.format(Locale.US, "%.1f", it) + " avg" },
                if (stats.brewsToday > 0) "${stats.brewsToday} today" else "None yet today",
            )
            Text(parts.joinToString(" · "), maxLines = 1, style = TextStyle(fontSize = 11.sp, color = colors.onSurfaceVariant))
        } else {
            Text(
                if (snapshot == null) "Open BrewLog once to see your stats here." else "No brews logged yet.",
                style = TextStyle(fontSize = 12.sp, color = colors.onSurfaceVariant),
            )
        }
    }
}

@androidx.compose.runtime.Composable
private fun DayBarsRow(perDay: List<Int>, colors: androidx.glance.color.ColorProviders) {
    val maxCount = maxOf(perDay.maxOrNull() ?: 0, 1)
    Row(
        modifier = GlanceModifier.fillMaxWidth().height(18.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        perDay.forEachIndexed { index, count ->
            val isToday = index == perDay.size - 1
            val barHeight = if (count == 0) 2.dp else (2 + (count * 16 / maxCount)).coerceIn(2, 18).dp
            val barColor = if (isToday) colors.primary else if (count > 0) colors.primaryContainer else colors.surfaceVariant
            Box(
                modifier = GlanceModifier.defaultWeight().height(18.dp),
                contentAlignment = Alignment.BottomCenter,
            ) {
                Box(
                    modifier = GlanceModifier.fillMaxWidth().height(barHeight).background(barColor).cornerRadius(2.dp),
                ) {}
            }
            if (index < perDay.size - 1) {
                Spacer(GlanceModifier.width(2.dp))
            }
        }
    }
}

// MARK: - Beans left

/** "Beans left": cups left, bag progress indicator, and freshness. */
class BeansLeftWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = WidgetSync.load(context)
        provideContent { GlanceTheme { BeansLeftContent(context, snapshot) } }
    }
}

class BeansLeftWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = BeansLeftWidget()
}

@androidx.compose.runtime.Composable
private fun BeansLeftContent(context: Context, snapshot: WidgetSnapshot?) {
    val colors = GlanceTheme.colors
    val bean = snapshot?.bean
    Column(
        GlanceModifier.fillMaxSize().background(colors.widgetBackground).cornerRadius(20.dp).padding(14.dp)
            .clickable(actionStartActivity(WidgetSync.link(context, "beans"))),
    ) {
        Text("Beans left", style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 12.sp, color = colors.primary))
        Spacer(GlanceModifier.height(2.dp))
        if (bean != null) {
            Text(bean.name, maxLines = 1, style = TextStyle(fontWeight = FontWeight.Bold, fontSize = 14.sp, color = colors.onSurface))
            val isLow = (bean.cupsLeft ?: Int.MAX_VALUE) < 3
            val countText = bean.cupsLeft?.toString() ?: bean.remaining.toInt().toString()
            val unitText = if (bean.cupsLeft != null) (if (bean.cupsLeft == 1) " cup" else " cups") else " g"
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    countText,
                    style = TextStyle(
                        fontWeight = FontWeight.Bold,
                        fontSize = 26.sp,
                        color = if (isLow) colors.error else colors.onSurface,
                    ),
                )
                Spacer(GlanceModifier.width(2.dp))
                Text(unitText, style = TextStyle(fontSize = 12.sp, color = colors.onSurfaceVariant))
            }
            Spacer(GlanceModifier.height(4.dp))
            LinearProgressIndicator(
                bean.fraction.toFloat(),
                GlanceModifier.fillMaxWidth(),
                color = if (isLow) colors.error else colors.primary,
                backgroundColor = colors.surfaceVariant,
            )
            Spacer(GlanceModifier.height(4.dp))
            val days = bean.daysOffRoast()
            val fresh = bean.freshness()
            val freshText = if (fresh != null && days != null) "${fresh.title} · day $days" else days?.let { "$it d off roast" }
            if (freshText != null) {
                Text(freshText, maxLines = 1, style = TextStyle(fontSize = 11.sp, color = colors.onSurfaceVariant))
            }
        } else {
            Text(
                if (snapshot == null) "Open BrewLog once to see your beans here." else "Pick beans on the Brew tab.",
                style = TextStyle(fontSize = 12.sp, color = colors.onSurfaceVariant),
            )
        }
    }
}
