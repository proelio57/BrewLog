package com.brewlog.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Scale
import androidx.compose.material.icons.filled.VerticalAlignBottom
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.brewlog.app.LocalContainer
import com.brewlog.app.brewing.BrewSession
import com.brewlog.app.domain.AppSettings
import com.brewlog.app.domain.WeightSample
import com.brewlog.app.domain.fmt1
import com.brewlog.app.domain.mmss
import com.brewlog.app.domain.scaleReadout
import com.brewlog.app.scale.ScaleManager
import com.brewlog.app.scale.monotonicMillis
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.BrewChart
import com.brewlog.app.ui.theme.GoodGreen
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.abs

/** "Just weigh": a plain scale + timer, with no recipe and nothing saved. Port of QuickWeighModel. */
private class QuickWeighModel(private val scale: ScaleManager, private val settings: () -> AppSettings) {
    var weight by mutableDoubleStateOf(scale.weight.value)
    var flow by mutableDoubleStateOf(0.0)
    var elapsed by mutableDoubleStateOf(0.0)
    var isRunning by mutableStateOf(false)
    /** Waiting for the first pour after a tare (auto-start). */
    var isArmed by mutableStateOf(false)
    val samples = mutableStateListOf<WeightSample>()
    var autoStart = true

    private var startMs: Long? = null
    private var accumulated = 0.0
    private val recent = ArrayDeque<Pair<Long, Double>>()
    private var awaitingZero = false
    private var lastSampleT = -1.0

    fun tare() {
        scale.tare()
        reset()
        // Arm only once the scale reports ~0 g, so the pre-tare weight can't trigger a start.
        awaitingZero = true
    }

    fun toggleTimer() = if (isRunning) pause() else start()

    fun reset() {
        pause()
        accumulated = 0.0
        elapsed = 0.0
        samples.clear()
        lastSampleT = -1.0
        isArmed = false
    }

    private fun start() {
        startMs = monotonicMillis()
        isRunning = true
        isArmed = false
    }

    private fun pause() {
        startMs?.let { accumulated += (monotonicMillis() - it) / 1000.0 }
        startMs = null
        isRunning = false
    }

    fun tick() {
        elapsed = accumulated + (startMs?.let { (monotonicMillis() - it) / 1000.0 } ?: 0.0)
    }

    fun ingest(grams: Double, atMs: Long) {
        if (!grams.isFinite()) return
        weight = grams
        recent.addLast(atMs to grams)
        while (recent.isNotEmpty() && atMs - recent.first().first > 3_000) recent.removeFirst()
        while (recent.size > BrewSession.MAX_RECENT_READINGS) recent.removeFirst()
        flow = BrewSession.slope(recent, 1.2, atMs)

        if (awaitingZero && abs(grams) < 1) {
            awaitingZero = false
            isArmed = autoStart
        }
        if (isArmed && !isRunning && grams >= settings().autoStartThreshold) start()
        if (isRunning) {
            val t = accumulated + (startMs?.let { (atMs - it) / 1000.0 } ?: 0.0)
            if (t - lastSampleT >= 0.2 && samples.size < 9_000) {
                samples.add(WeightSample(t, grams))
                lastSampleT = t
            }
        }
    }
}

@Composable
fun QuickWeighScreen(onClose: () -> Unit) {
    val container = LocalContainer.current
    val settings by container.settings.settings.collectAsStateWithLifecycle()
    val ready by container.scale.ready.collectAsStateWithLifecycle()
    val model = remember { QuickWeighModel(container.scale) { container.settings.current } }
    var showScale by remember { mutableStateOf(false) }
    model.autoStart = settings.quickWeighAutoStart

    LaunchedEffect(Unit) { container.scale.readings.collect { model.ingest(it.grams, it.timeMillis) } }
    LaunchedEffect(Unit) {
        while (isActive) {
            model.tick()
            delay(100)
        }
    }
    val view = LocalView.current
    DisposableEffect(settings.keepAwake) {
        view.keepScreenOn = settings.keepAwake
        onDispose { view.keepScreenOn = false }
    }

    Column(
        Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).systemBarsPadding().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose, modifier = Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant)) {
                Icon(Icons.Filled.Close, contentDescription = "Close")
            }
            Text("Quick weigh", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Row(Modifier.clickable { showScale = true }.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(if (ready) GoodGreen else MaterialTheme.colorScheme.onSurfaceVariant))
                Spacer(Modifier.width(4.dp))
                Icon(Icons.Filled.Scale, contentDescription = "Scale connection", modifier = Modifier.size(16.dp))
            }
        }
        if (!ready) {
            BrewCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Scale, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text("No scale connected", fontWeight = FontWeight.SemiBold)
                        Text("Connect your scale (BOOKOO or Timemore Dot) or turn on the demo scale.", style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Button(onClick = { showScale = true }) { Text("Connect") }
                }
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(model.weight.scaleReadout(), fontSize = 88.sp, fontWeight = FontWeight.SemiBold, style = TextStyle(fontFeatureSettings = "tnum"), maxLines = 1)
            Text("grams · ${fmt1(maxOf(model.flow, 0.0))} g/s", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(model.elapsed.mmss(), fontSize = 44.sp, fontWeight = FontWeight.Medium, style = TextStyle(fontFeatureSettings = "tnum"))
            Text(
                when {
                    model.isRunning -> "Timer running"
                    model.isArmed -> "Start pouring, the timer starts automatically"
                    model.autoStart -> "Tare, then pour. The timer starts by itself"
                    else -> "Press Start when you pour"
                },
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = if (model.isArmed) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            RoundButton("Tare", Icons.Filled.VerticalAlignBottom) { model.tare(); container.haptics.tap() }
            RoundButton(if (model.isRunning) "Pause" else "Start", if (model.isRunning) Icons.Filled.Pause else Icons.Filled.PlayArrow, prominent = true) {
                model.toggleTimer(); container.haptics.tap()
            }
            RoundButton("Reset", Icons.Filled.Refresh) { model.reset() }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Start the timer when I start pouring", Modifier.weight(1f))
            Switch(checked = settings.quickWeighAutoStart, onCheckedChange = { value -> container.settings.update { it.copy(quickWeighAutoStart = value) } })
        }
        if (model.samples.size > 2) {
            BrewChart(model.samples.toList(), recipe = null, currentTime = if (model.isRunning) model.elapsed else null, height = 160.dp)
        }
    }
    if (showScale) ScaleSheet { showScale = false }
}

@Composable
private fun RoundButton(title: String, icon: ImageVector, prominent: Boolean = false, onClick: () -> Unit) {
    Column(
        Modifier.clip(RoundedCornerShape(16.dp)).clickable(onClick = onClick).padding(4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.size(72.dp).clip(CircleShape)
                .background(if (prominent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = title, tint = if (prominent) Color.White else MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.size(30.dp))
        }
        Spacer(Modifier.height(6.dp))
        Text(title, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
