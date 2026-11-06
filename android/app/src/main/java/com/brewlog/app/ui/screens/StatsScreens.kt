package com.brewlog.app.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.brewlog.app.analysis.BrewStats
import com.brewlog.app.analysis.statsEntry
import com.brewlog.app.data.BrewRepository
import com.brewlog.app.domain.Bean
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.mmss
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.CapsuleOption
import com.brewlog.app.ui.components.CapsuleSwitch
import com.brewlog.app.ui.components.SectionHeader
import com.brewlog.app.ui.components.StatView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Pour-over and espresso statistics: activity, rating trend, brewing numbers, beans and recipes.
 * Port of Views/Stats/StatsView.swift and StatsCharts.swift.
 */
@Composable
fun StatsContent(
    brews: List<Brew>,
    beans: Map<String, Bean>,
    repo: BrewRepository,
    modifier: Modifier = Modifier,
) {
    var kind by rememberSaveable { mutableStateOf("pourOver") }
    var rangeDays by rememberSaveable { mutableIntStateOf(90) }

    val espresso = kind == "espresso"
    val now = remember { System.currentTimeMillis() }
    val since = if (rangeDays > 0) now - rangeDays * 86_400_000L else null

    val entries = remember(brews, espresso, since) {
        brews.map { brew ->
            val bean = brew.beanId?.let { beans[it] }
            val (samples, machineSamples) = if (espresso && brew.isEspresso) {
                repo.samples(brew.id) to repo.machineSamples(brew.id)
            } else null to null
            brew.statsEntry(
                beanName = bean?.name ?: "",
                samples = samples,
                machineSamples = machineSamples,
            )
        }
    }

    val summary = remember(entries, espresso, since) {
        BrewStats.summary(entries, espresso = espresso, since = since, now = now)
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Filter switches: Kind and Range
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CapsuleSwitch(
                options = listOf(
                    CapsuleOption("pourOver", "Pour-over", Icons.Filled.WaterDrop),
                    CapsuleOption("espresso", "Espresso", Icons.Filled.Coffee),
                ),
                selection = kind,
                onSelectionChanged = { kind = it },
            )
            CapsuleSwitch(
                options = listOf(
                    CapsuleOption(30, "30 days"),
                    CapsuleOption(90, "90 days"),
                    CapsuleOption(0, "All"),
                ),
                selection = rangeDays,
                onSelectionChanged = { rangeDays = it },
            )
        }

        // Headline summary card
        BrewCard {
            Row(Modifier.fillMaxWidth()) {
                StatView(
                    value = summary.brews.toString(),
                    label = if (espresso) "Shots" else "Brews",
                )
                StatView(
                    value = summary.averageRating?.let { String.format(Locale.US, "%.1f★", it) } ?: "–",
                    label = "Avg rating",
                )
                StatView(
                    value = summary.trend?.title ?: "–",
                    label = "Trend",
                )
            }
        }

        // Section: Activity
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeader("Activity")
            BrewCard {
                if (summary.brews == 0) {
                    EmptyRangeNotice()
                } else {
                    WeeklyBrewsChart(weeks = summary.weeks)
                }
            }
        }

        // Section: Rating
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeader("Rating")
            BrewCard {
                if (summary.brews == 0) {
                    EmptyRangeNotice()
                } else {
                    RatingTrendChart(weeks = summary.weeks, trend = summary.trend)
                }
            }
        }

        // Section: Shots or Brewing
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeader(if (espresso) "Shots" else "Brewing")
            BrewCard {
                if (summary.brews == 0) {
                    EmptyRangeNotice()
                } else if (espresso) {
                    EspressoStatsRows(summary)
                } else {
                    PourOverStatsRows(summary)
                }
            }
        }

        // Section: Beans
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeader("Beans")
            BrewCard {
                GroupsList(summary.beans, showsBest = true)
            }
        }

        // Section: Recipes
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeader("Recipes")
            BrewCard {
                GroupsList(summary.recipes, showsBest = false)
            }
        }

        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun PourOverStatsRows(summary: BrewStats.Summary) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        StatRow("Average time", summary.averageTime?.let { it.mmss() } ?: "–")
        StatRow("Against the recipe", summary.averageTimeDelta?.let { BrewStats.signedSeconds(it) } ?: "–")
        StatRow("Average ratio", summary.averageRatio?.let { String.format(Locale.US, "1:%.1f", it) } ?: "–")
        StatRow(
            title = "Extraction",
            value = summary.averageExtraction?.let { String.format(Locale.US, "%.1f %%", it) } ?: "–",
            detail = if (summary.extractionCount > 0) "${summary.extractionCount} with TDS" else "Log TDS to see it",
        )
    }
}

@Composable
private fun EspressoStatsRows(summary: BrewStats.Summary) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        StatRow("Shot time", summary.averageTime?.let { String.format(Locale.US, "%.0f s", it) } ?: "–")
        StatRow("Ratio", summary.averageRatio?.let { String.format(Locale.US, "1:%.1f", it) } ?: "–")
        StatRow(
            title = "First drops",
            value = summary.averageFirstDrops?.let { String.format(Locale.US, "%.0f s", it) } ?: "–",
            detail = "${summary.firstDropsCount} of ${summary.brews} shots",
        )
        StatRow(
            title = "Peak pressure",
            value = summary.averagePeakPressure?.let { String.format(Locale.US, "%.1f bar", it) } ?: "–",
            detail = "${summary.pressureCount} of ${summary.brews} shots",
        )
        StatRow(
            title = "Signs of channeling",
            value = "${summary.channelingShots} shot${if (summary.channelingShots == 1) "" else "s"}",
            detail = "Sudden pressure drop or first drops under 3 s",
        )
        if (summary.points.isNotEmpty()) {
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            ShotScatterChart(points = summary.points)
        }
    }
}

@Composable
private fun StatRow(title: String, value: String, detail: String? = null) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium)
            if (detail != null) {
                Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun GroupsList(groups: List<BrewStats.Group>, showsBest: Boolean) {
    if (groups.isEmpty()) {
        EmptyRangeNotice()
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        groups.take(10).forEachIndexed { index, group ->
            if (index > 0) {
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        group.name,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                    )
                    Text(
                        group.averageRating?.let { String.format(Locale.US, "%.1f★", it) } ?: "–",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                val parts = mutableListOf("${group.brews} brew${if (group.brews == 1) "" else "s"}")
                if (showsBest) {
                    group.bestRecipe?.let { parts.add("best: $it") }
                    group.bestGrind?.let { parts.add("grind $it") }
                }
                parts.add("last ${formatDayMonth(group.lastBrewed)}")
                Text(
                    parts.joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                )
            }
        }
    }
}

@Composable
private fun EmptyRangeNotice() {
    Text(
        "No brews in this range yet.",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.fillMaxWidth(),
    )
}

/** Brews per week, last 12 weeks. Tap a bar for its number. */
@Composable
fun WeeklyBrewsChart(weeks: List<BrewStats.Week>) {
    var selectedWeek by remember { mutableStateOf<BrewStats.Week?>(null) }
    val primaryColor = MaterialTheme.colorScheme.primary
    val gridColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        selectedWeek?.let { week ->
            ChartCalloutBadge(
                title = formatDayMonth(week.start),
                value = "${week.brews} brew${if (week.brews == 1) "" else "s"}",
            )
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(140.dp)
                .pointerInput(weeks) {
                    detectTapGestures { offset ->
                        val count = max(weeks.size, 1)
                        val slotWidth = size.width / count.toFloat()
                        val index = (offset.x / slotWidth).toInt().coerceIn(0, weeks.size - 1)
                        selectedWeek = weeks.getOrNull(index)
                    }
                },
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val maxBrews = max(weeks.maxOfOrNull { it.brews } ?: 1, 4)
                val count = max(weeks.size, 1)
                val slotWidth = size.width / count.toFloat()
                val barWidth = slotWidth * 0.6f

                // Horizontal grid lines
                for (step in 1..3) {
                    val y = size.height * (1f - step / 3f)
                    drawLine(
                        color = gridColor,
                        start = Offset(0f, y),
                        end = Offset(size.width, y),
                        strokeWidth = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 8f)),
                    )
                }

                weeks.forEachIndexed { i, week ->
                    val fraction = week.brews.toFloat() / maxBrews.toFloat()
                    val barHeight = size.height * fraction
                    val x = i * slotWidth + (slotWidth - barWidth) / 2f
                    val y = size.height - barHeight
                    val alpha = if (selectedWeek == null || selectedWeek == week) 1f else 0.35f

                    drawRoundRect(
                        color = primaryColor.copy(alpha = alpha),
                        topLeft = Offset(x, y),
                        size = Size(barWidth, barHeight),
                        cornerRadius = CornerRadius(4.dp.toPx(), 4.dp.toPx()),
                    )
                }
            }
        }
    }
}

/** Average rating per week with the trend verdict. */
@Composable
fun RatingTrendChart(weeks: List<BrewStats.Week>, trend: BrewStats.Trend?) {
    var selectedWeek by remember { mutableStateOf<BrewStats.Week?>(null) }
    val primaryColor = MaterialTheme.colorScheme.primary
    val gridColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (trend != null) {
            Text(
                "${trend.title} rating trend",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = primaryColor,
            )
        } else {
            Text(
                "Rate brews in 3 different weeks to see a trend.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        selectedWeek?.let { week ->
            val rating = week.averageRating
            if (rating != null) {
                ChartCalloutBadge(
                    title = formatDayMonth(week.start),
                    value = String.format(Locale.US, "%.1f ★", rating),
                )
            }
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(140.dp)
                .pointerInput(weeks) {
                    detectTapGestures { offset ->
                        val ratedWeeks = weeks.mapIndexedNotNull { index, w -> if (w.averageRating != null) index to w else null }
                        if (ratedWeeks.isNotEmpty()) {
                            val count = max(weeks.size, 1)
                            val slotWidth = size.width / count.toFloat()
                            val closest = ratedWeeks.minByOrNull { (index, _) ->
                                abs((index + 0.5f) * slotWidth - offset.x)
                            }
                            selectedWeek = closest?.second
                        }
                    }
                },
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                // Horizontal grid lines for ratings 1, 3, 5
                listOf(1f, 3f, 5f).forEach { r ->
                    val y = size.height * (1f - r / 5f)
                    drawLine(
                        color = gridColor,
                        start = Offset(0f, y),
                        end = Offset(size.width, y),
                        strokeWidth = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 8f)),
                    )
                }

                val count = max(weeks.size, 1)
                val slotWidth = size.width / count.toFloat()
                val ratedPoints = mutableListOf<Offset>()

                weeks.forEachIndexed { i, week ->
                    val r = week.averageRating ?: return@forEachIndexed
                    val x = (i + 0.5f) * slotWidth
                    val y = size.height * (1f - (r.toFloat() / 5f))
                    ratedPoints.add(Offset(x, y))
                }

                // Connect with line
                if (ratedPoints.size >= 2) {
                    val path = Path().apply {
                        moveTo(ratedPoints.first().x, ratedPoints.first().y)
                        for (j in 1 until ratedPoints.size) {
                            lineTo(ratedPoints[j].x, ratedPoints[j].y)
                        }
                    }
                    drawPath(
                        path = path,
                        color = primaryColor,
                        style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round),
                    )
                }

                // Draw dots
                ratedPoints.forEach { pt ->
                    drawCircle(color = primaryColor, radius = 4.5.dp.toPx(), center = pt)
                }
            }
        }
    }
}

/** Espresso shots: shot time against ratio, darker = better rated. Tap a dot for its numbers. */
@Composable
fun ShotScatterChart(points: List<BrewStats.Point>) {
    var selectedPoint by remember { mutableStateOf<BrewStats.Point?>(null) }
    val primaryColor = MaterialTheme.colorScheme.primary
    val gridColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)

    val minTime = points.minOfOrNull { it.time }?.coerceAtMost(15.0) ?: 15.0
    val maxTime = points.maxOfOrNull { it.time }?.coerceAtLeast(45.0) ?: 45.0
    val minRatio = points.minOfOrNull { it.ratio }?.coerceAtMost(1.2) ?: 1.2
    val maxRatio = points.maxOfOrNull { it.ratio }?.coerceAtLeast(3.0) ?: 3.0

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        selectedPoint?.let { pt ->
            ChartCalloutBadge(
                title = String.format(Locale.US, "%.0f s · 1:%.1f", pt.time, pt.ratio),
                value = if (pt.rating > 0) "${pt.rating} ★" else "Not rated",
            )
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(180.dp)
                .pointerInput(points) {
                    detectTapGestures { offset ->
                        val spanTime = max(maxTime - minTime, 1.0)
                        val spanRatio = max(maxRatio - minRatio, 0.1)
                        selectedPoint = points.minByOrNull { pt ->
                            val x = size.width * ((pt.time - minTime) / spanTime).toFloat()
                            val y = size.height * (1f - ((pt.ratio - minRatio) / spanRatio).toFloat())
                            val dx = x - offset.x
                            val dy = y - offset.y
                            sqrt(dx * dx + dy * dy)
                        }
                    }
                },
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                // Background grid lines
                for (s in 1..3) {
                    val y = size.height * (s / 4f)
                    drawLine(
                        color = gridColor,
                        start = Offset(0f, y),
                        end = Offset(size.width, y),
                        strokeWidth = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 8f)),
                    )
                }

                val spanTime = max(maxTime - minTime, 1.0)
                val spanRatio = max(maxRatio - minRatio, 0.1)

                points.forEach { pt ->
                    val x = size.width * ((pt.time - minTime) / spanTime).toFloat()
                    val y = size.height * (1f - ((pt.ratio - minRatio) / spanRatio).toFloat())
                    val alpha = if (pt.rating > 0) {
                        0.3f + 0.7f * (pt.rating.coerceIn(1, 5) / 5f)
                    } else 0.4f
                    val dotColor = if (pt.rating > 0) primaryColor.copy(alpha = alpha) else Color.Gray.copy(alpha = 0.5f)

                    val isSelected = selectedPoint == pt
                    if (isSelected) {
                        drawCircle(
                            color = primaryColor.copy(alpha = 0.3f),
                            radius = 12.dp.toPx(),
                            center = Offset(x, y),
                        )
                    }
                    drawCircle(
                        color = dotColor,
                        radius = 6.dp.toPx(),
                        center = Offset(x, y),
                    )
                }
            }
        }
    }
}

@Composable
private fun ChartCalloutBadge(title: String, value: String) {
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier.padding(bottom = 2.dp),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
        }
    }
}

private fun formatDayMonth(millis: Long): String {
    val sdf = SimpleDateFormat("d MMM", Locale.getDefault())
    return sdf.format(Date(millis))
}
