package com.brewlog.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Scale
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.brewlog.app.BrewConfig
import com.brewlog.app.LocalContainer
import com.brewlog.app.brewing.BrewCue
import com.brewlog.app.brewing.BrewPhase
import com.brewlog.app.brewing.BrewSession
import com.brewlog.app.brewing.BrewSnapshot
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.RecipeStep
import com.brewlog.app.domain.ValveState
import com.brewlog.app.domain.fmt1
import com.brewlog.app.domain.grams
import com.brewlog.app.domain.grams1
import com.brewlog.app.domain.mmss
import com.brewlog.app.domain.scaleReadout
import com.brewlog.app.ui.Routes
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.BrewChart
import com.brewlog.app.ui.components.icon
import com.brewlog.app.ui.theme.GoodGreen
import com.brewlog.app.ui.theme.InfoBlue
import com.brewlog.app.ui.theme.WarnOrange
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.ceil

private val tabular = TextStyle(fontFeatureSettings = "tnum")

@Composable
fun LiveBrewScreen(nav: NavHostController) {
    val container = LocalContainer.current
    val active = container.activeBrew
    if (active == null) {
        LaunchedEffect(Unit) { nav.popBackStack() }
        return
    }
    val (config, session) = active
    val snapshot by session.state.collectAsStateWithLifecycle()
    val settings by container.settings.settings.collectAsStateWithLifecycle()
    val scaleReady by container.scale.ready.collectAsStateWithLifecycle()
    val pressureReady by container.pressure.ready.collectAsStateWithLifecycle()
    val currentPressure by container.pressure.pressure.collectAsStateWithLifecycle()
    val pressureSamples = remember { androidx.compose.runtime.mutableStateListOf<com.brewlog.app.domain.PressureSample>() }
    var confirmDiscard by remember { mutableStateOf(false) }

    fun close() {
        if (pressureReady) container.pressure.brewFinished()
        session.discard()
        container.activeBrew = null
        nav.popBackStack()
    }

    fun finish() {
        if (session.phase != BrewPhase.BREWING) return
        if (pressureReady) container.pressure.brewFinished()
        session.finish()
        val brew = Brew(
            recipeId = config.recipe.id,
            recipeName = config.recipe.name,
            recipe = config.recipe,
            dose = config.dose,
            targetWater = config.recipe.water,
            finalWeight = session.finalWeight,
            totalTime = session.elapsed,
            waterTemp = config.waterTemp,
            grindSetting = config.grindText,
            grindValue = config.grindValue,
            brewerId = config.brewer?.id,
            brewerName = config.brewer?.name ?: "",
            grinderId = config.grinder?.id,
            grinderName = config.grinder?.name ?: "",
            grinderSpec = config.grinder?.grinder,
            filterId = config.filter?.id,
            filterName = config.filter?.name ?: "",
            filterFlow = config.filter?.filterFlow,
            filterIdealRoast = config.filter?.idealRoast,
            beanId = config.beanId,
            usedScale = session.usesScale,
            pressureSamples = if (pressureReady) pressureSamples.toList() else emptyList(),
        )
        container.repository.saveNewBrew(brew, if (session.usesScale) session.recordedSamples() else emptyList())
        container.activeBrew = null
        nav.navigate(Routes.brewDetail(brew.id, isNew = true)) { popUpTo(Routes.LIVE) { inclusive = true } }
    }

    LaunchedEffect(session) {
        session.onAutoFinish = { finish() }
        container.scale.readings.collect { session.ingest(it.grams, it.timeMillis) }
    }
    LaunchedEffect(pressureReady, snapshot.phase) {
        if (pressureReady && snapshot.phase == BrewPhase.BREWING) {
            container.pressure.startMonitoring()
        }
    }
    LaunchedEffect(pressureReady) {
        if (pressureReady) {
            container.pressure.readings.collect { r ->
                if (snapshot.phase == BrewPhase.BREWING) {
                    pressureSamples.add(com.brewlog.app.domain.PressureSample(snapshot.elapsed, r.bar))
                }
            }
        }
    }
    LaunchedEffect(session) {
        while (isActive) {
            session.tick()
            delay(50)
        }
    }
    val view = LocalView.current
    DisposableEffect(settings.keepAwake) {
        view.keepScreenOn = settings.keepAwake
        onDispose { view.keepScreenOn = false }
    }
    val context = androidx.compose.ui.platform.LocalContext.current
    LaunchedEffect(snapshot.phase, snapshot.elapsed.toLong(), snapshot.currentStepIndex) {
        if (snapshot.phase == BrewPhase.BREWING) {
            com.brewlog.app.brewing.BrewNotificationManager.show(context, config, snapshot)
        } else {
            com.brewlog.app.brewing.BrewNotificationManager.dismiss(context)
        }
    }
    DisposableEffect(Unit) {
        onDispose {
            com.brewlog.app.brewing.BrewNotificationManager.dismiss(context)
        }
    }

    BackHandler {
        if (snapshot.phase == BrewPhase.BREWING) confirmDiscard = true else close()
    }

    Column(
        Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).systemBarsPadding().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Header(config, snapshot.usesScale && scaleReady, pressureLive = pressureReady) { if (snapshot.phase == BrewPhase.BREWING) confirmDiscard = true else close() }
        Readouts(snapshot, config, pressureReady = pressureReady, pressureBar = currentPressure)
        when (snapshot.phase) {
            BrewPhase.PREPARING -> PreparingCard(snapshot.usesScale)
            BrewPhase.ARMED -> ArmedCard(snapshot, config.recipe.steps.firstOrNull())
            else -> ActiveStepCard(snapshot, session)
        }
        if (snapshot.phase == BrewPhase.BREWING || snapshot.phase == BrewPhase.FINISHED) {
            BrewChart(
                snapshot.samples,
                config.recipe,
                currentTime = snapshot.elapsed,
                height = 160.dp,
                pressureSamples = if (pressureReady) pressureSamples.toList() else emptyList(),
            )
        } else {
            PreparationList(config)
        }
        StepsStrip(config, snapshot)
        Spacer(Modifier.weight(1f))
        Controls(
            snapshot,
            onReady = {
                session.ready()
                if (pressureReady) container.pressure.prepareForBrew(config.recipe)
                container.haptics.tap()
            },
            onStart = { session.startManually() },
            onFinish = { finish() },
        )
        Spacer(Modifier.height(4.dp))
    }

    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text("Discard this brew?") },
            confirmButton = { TextButton(onClick = { confirmDiscard = false; close() }) { Text("Discard", color = Color(0xFFFF3B30)) } },
            dismissButton = { TextButton(onClick = { confirmDiscard = false }) { Text("Keep brewing") } },
        )
    }
}

@Composable
private fun Header(config: BrewConfig, scaleLive: Boolean, pressureLive: Boolean = false, onClose: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onClose, modifier = Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant)) {
            Icon(Icons.Filled.Close, contentDescription = "Close")
        }
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(config.recipe.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text("${config.dose.grams1()} : ${config.recipe.water.grams()} · ${config.waterTemp.toInt()} °C",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.End) {
            if (pressureLive) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(Color(0xFFFF9800)))
                Spacer(Modifier.width(4.dp))
                Icon(Icons.Filled.Speed, contentDescription = "Pressure monitor connected", modifier = Modifier.size(16.dp), tint = Color(0xFFFF9800))
                Spacer(Modifier.width(8.dp))
            }
            Box(Modifier.size(8.dp).clip(CircleShape).background(if (scaleLive) GoodGreen else MaterialTheme.colorScheme.onSurfaceVariant))
            Spacer(Modifier.width(4.dp))
            Icon(Icons.Filled.Scale, null, Modifier.size(16.dp))
        }
    }
}

@Composable
private fun Readouts(
    snapshot: BrewSnapshot,
    config: BrewConfig,
    pressureReady: Boolean = false,
    pressureBar: Double = 0.0,
) {
    val fontSize = if (pressureReady) 38.sp else 54.sp
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        Column(Modifier.weight(1f)) {
            Text("TIME", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(snapshot.elapsed.mmss(), fontSize = fontSize, fontWeight = FontWeight.SemiBold, style = tabular, maxLines = 1)
            val late = snapshot.phase == BrewPhase.BREWING && snapshot.elapsed >= config.recipe.targetTime
            Text("target ${config.recipe.targetTime.mmss()}", style = MaterialTheme.typography.bodySmall,
                color = if (late) WarnOrange else MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (pressureReady) {
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("PRESSURE", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = Color(0xFFFF9800))
                Text(String.format(java.util.Locale.US, "%.1f", pressureBar), fontSize = fontSize, fontWeight = FontWeight.SemiBold, style = tabular, color = Color(0xFFFF9800), maxLines = 1)
                Text("bar", style = MaterialTheme.typography.bodySmall, color = Color(0xFFFF9800))
            }
        }
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.End) {
            Text("WEIGHT", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (snapshot.usesScale) {
                val shown = if (snapshot.phase == BrewPhase.PREPARING) snapshot.weight else maxOf(snapshot.weight, 0.0)
                Text(shown.scaleReadout(), fontSize = fontSize, fontWeight = FontWeight.SemiBold, style = tabular, maxLines = 1)
                Text("${fmt1(maxOf(snapshot.flowRate, 0.0))} g/s", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                Text(snapshot.activeTarget?.let { "→${it.toInt()}" } ?: "–", fontSize = fontSize, fontWeight = FontWeight.SemiBold, style = tabular)
                Text("no scale", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun PreparingCard(usesScale: Boolean) {
    BrewCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Scale, null, Modifier.size(32.dp), tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(14.dp))
            Column {
                Text("Put the brewer with coffee on the scale", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    if (usesScale) "Press Ready to tare. The timer starts by itself when you start pouring."
                    else "No scale connected. Press Ready, then start the timer when you pour.",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun ArmedCard(snapshot: BrewSnapshot, first: RecipeStep?) {
    val transition = rememberInfiniteTransition(label = "pulse")
    val pulse by transition.animateFloat(0.9f, 1.25f, infiniteRepeatable(tween(1100), RepeatMode.Reverse), label = "pulse")
    BrewCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(contentAlignment = Alignment.Center) {
                Box(Modifier.size(56.dp).scale(pulse).clip(CircleShape).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)))
                Icon(Icons.Filled.WaterDrop, null, Modifier.size(30.dp), tint = MaterialTheme.colorScheme.primary)
            }
            Spacer(Modifier.width(14.dp))
            Column {
                Text(if (snapshot.usesScale) "Start pouring" else "Ready when you are", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                if (first != null) {
                    Text(first.headline + (first.note?.let { ". $it" } ?: ""), style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (snapshot.usesScale) {
                    Text(if (snapshot.zeroConfirmed) "Timer starts automatically" else "Taring…", style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

@Composable
private fun ActiveStepCard(snapshot: BrewSnapshot, session: BrewSession) {
    val recipe = session.recipe
    val current = snapshot.currentStepIndex?.let { recipe.steps[it] }
    val next = snapshot.nextStepIndex?.let { recipe.steps[it] }
    val flashColor = when (snapshot.flash) {
        BrewCue.TARGET -> GoodGreen
        BrewCue.NEXT_STEP -> MaterialTheme.colorScheme.primary
        BrewCue.FINISH -> InfoBlue
        else -> Color.Transparent
    }
    Box(Modifier.border(if (snapshot.flash != null) 3.dp else 0.dp, flashColor, RoundedCornerShape(20.dp))) {
        BrewCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (current != null) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(current.kind.icon, null, Modifier.size(22.dp))
                            Spacer(Modifier.width(6.dp))
                            Text(current.headline, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        }
                        current.valve?.let { valve ->
                            val open = valve == ValveState.OPEN
                            Text(if (open) "Valve open" else "Valve closed", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold,
                                modifier = Modifier.clip(RoundedCornerShape(50)).background((if (open) GoodGreen else WarnOrange).copy(alpha = 0.18f))
                                    .padding(horizontal = 8.dp, vertical = 3.dp))
                        }
                        current.note?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 3) }
                    }
                    val target = snapshot.activeTarget
                    if (snapshot.usesScale && target != null) {
                        PourProgressBar(snapshot.weight, snapshot.activePourBase, target, target - snapshot.pingLead)
                        val over = snapshot.overpour
                        when {
                            over != null -> Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.Warning, null, Modifier.size(16.dp), tint = WarnOrange)
                                Spacer(Modifier.width(4.dp))
                                Text("Over by ${over.toInt()} g", color = WarnOrange, fontWeight = FontWeight.SemiBold)
                            }
                            snapshot.weight >= target - snapshot.pingLead -> Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.CheckCircle, null, Modifier.size(16.dp), tint = GoodGreen)
                                Spacer(Modifier.width(4.dp))
                                Text("Target reached, stop pouring", color = GoodGreen, fontWeight = FontWeight.SemiBold)
                            }
                            else -> Text("${(target - snapshot.weight).toInt()} g to go", color = MaterialTheme.colorScheme.onSurfaceVariant, style = tabular)
                        }
                    }
                }
                Spacer(Modifier.width(12.dp))
                CountdownRing(
                    progress = snapshot.countdownProgress.toFloat(),
                    remaining = snapshot.timeToNextStep,
                    overtime = if (next == null) snapshot.elapsed - recipe.targetTime else null,
                    label = next?.let { if (it.kind.isPour && it.target != null) "→ ${it.target.toInt()} g" else it.kind.title } ?: "Drawdown",
                )
            }
        }
    }
}

@Composable
private fun PourProgressBar(weight: Double, base: Double, target: Double, pingAt: Double) {
    val span = maxOf(target - base, 1.0)
    val fraction = ((weight - base) / span).coerceIn(0.0, 1.0).toFloat()
    val pingFraction = ((pingAt - base) / span).coerceIn(0.0, 1.0).toFloat()
    val color = when {
        weight > target + 2 -> WarnOrange
        weight >= pingAt -> GoodGreen
        else -> MaterialTheme.colorScheme.primary
    }
    BoxWithConstraints(Modifier.fillMaxWidth().height(16.dp), contentAlignment = Alignment.CenterStart) {
        Box(Modifier.fillMaxWidth().height(12.dp).clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.surfaceVariant))
        Box(Modifier.fillMaxWidth(fraction).height(12.dp).clip(RoundedCornerShape(50)).background(color))
        Box(Modifier.offset(x = maxWidth * pingFraction - 1.dp).width(2.dp).height(16.dp)
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)))
    }
}

@Composable
private fun CountdownRing(progress: Float, remaining: Double?, overtime: Double?, label: String) {
    val track = MaterialTheme.colorScheme.surfaceVariant
    val ringColor = if (remaining != null && remaining <= 5) WarnOrange else MaterialTheme.colorScheme.primary
    Box(Modifier.size(96.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize().padding(4.dp)) {
            val stroke = Stroke(width = 8.dp.toPx(), cap = StrokeCap.Round)
            drawArc(track, 0f, 360f, useCenter = false, style = stroke)
            drawArc(ringColor, -90f, 360f * progress, useCenter = false, style = stroke)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            when {
                remaining != null -> Text(ceil(remaining).mmss(), fontWeight = FontWeight.Bold, fontSize = 20.sp, style = tabular)
                overtime != null -> Text(if (overtime >= 0) "+${overtime.mmss()}" else ceil(-overtime).mmss(), fontWeight = FontWeight.Bold,
                    fontSize = 20.sp, style = tabular, color = if (overtime >= 0) WarnOrange else MaterialTheme.colorScheme.onSurface)
            }
            Text(label, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }
    }
}

@Composable
private fun PreparationList(config: BrewConfig) {
    val grind = when {
        config.grindValue != null && config.grinder != null -> ", ground at ${config.grinder.grinder.format(config.grindValue)}"
        config.grindText.isNotEmpty() -> ", ground ${config.grindText}"
        else -> ""
    }
    BrewCard {
        listOf(
            "Rinse the paper with hot water and discard it",
            "Add ${config.dose.grams1()} of coffee$grind",
            "Shake or swirl to level the bed",
            "Water at ${config.waterTemp.toInt()} °C",
        ).forEachIndexed { index, text ->
            Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(22.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant), contentAlignment = Alignment.Center) {
                    Text("${index + 1}", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.width(10.dp))
                Text(text, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
private fun StepsStrip(config: BrewConfig, snapshot: BrewSnapshot) {
    val listState = rememberLazyListState()
    val current = snapshot.currentStepIndex
    LaunchedEffect(current) { if (current != null) listState.animateScrollToItem(maxOf(current - 1, 0)) }
    LazyRow(state = listState, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        itemsIndexed(config.recipe.steps) { index, step ->
            val brewing = snapshot.phase == BrewPhase.BREWING || snapshot.phase == BrewPhase.FINISHED
            val done = brewing && current != null && index < current
            val isCurrent = brewing && current == index
            Row(
                Modifier.clip(RoundedCornerShape(12.dp))
                    .background(if (isCurrent) MaterialTheme.colorScheme.primary.copy(alpha = 0.15f) else MaterialTheme.colorScheme.surface)
                    .border(1.5.dp, if (isCurrent) MaterialTheme.colorScheme.primary else Color.Transparent, RoundedCornerShape(12.dp))
                    .padding(horizontal = 10.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(if (done) Icons.Filled.CheckCircle else step.kind.icon, null, Modifier.size(18.dp),
                    tint = when {
                        done -> GoodGreen
                        isCurrent -> MaterialTheme.colorScheme.primary
                        else -> MaterialTheme.colorScheme.onSurfaceVariant
                    })
                Spacer(Modifier.width(6.dp))
                Column {
                    Text(step.time.mmss(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(if (step.kind.isPour) "${(step.target ?: 0.0).toInt()} g" else step.kind.title,
                        style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun Controls(snapshot: BrewSnapshot, onReady: () -> Unit, onStart: () -> Unit, onFinish: () -> Unit) {
    when (snapshot.phase) {
        BrewPhase.PREPARING -> PrimaryButton("Ready", Icons.Filled.CheckCircle, onClick = onReady)
        BrewPhase.ARMED -> if (snapshot.usesScale) {
            TextButton(onClick = onStart, modifier = Modifier.fillMaxWidth()) { Text("Start timer manually", fontWeight = FontWeight.SemiBold) }
        } else {
            PrimaryButton("Start timer", Icons.Filled.PlayArrow, onClick = onStart)
        }
        BrewPhase.BREWING -> PrimaryButton("Finish · drawdown done", Icons.Filled.Stop, color = GoodGreen, onClick = onFinish)
        BrewPhase.FINISHED -> Unit
    }
}
