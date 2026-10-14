package com.brewlog.app.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.brewlog.app.LocalContainer
import com.brewlog.app.analysis.BrewAnalyzer
import com.brewlog.app.domain.PressureSample
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.WeightSample
import com.brewlog.app.domain.fmt1
import com.brewlog.app.domain.mmss
import com.brewlog.app.ui.theme.FlowTeal
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

val PressureAmber = Color(0xFFFF9800)

/** Precomputed series and axis scaling. Port of BrewChartModel (BrewChart.swift). */
private class ChartModel(
    samples: List<WeightSample>,
    recipe: Recipe?,
    currentTime: Double?,
    pressureSamples: List<PressureSample> = emptyList(),
) {
    val weight: List<Pair<Double, Double>>
    val flow: List<Pair<Double, Double>>
    val pressure: List<Pair<Double, Double>>
    val target: List<Pair<Double, Double>> = recipe?.targetCurve() ?: emptyList()
    val stepTimes: List<Double> = recipe?.steps?.map { it.time } ?: emptyList()
    val maxT: Double
    val maxW: Double
    val maxFlow: Double
    val maxPressure: Double = 12.0
    val flowTicks: List<Double>
    val weightTicks: List<Double>
    val pressureTicks: List<Double> = listOf(3.0, 6.0, 9.0, 12.0)

    init {
        val flows = BrewAnalyzer.centeredFlows(samples)
        val lastT = maxOf(samples.lastOrNull()?.t ?: 0.0, pressureSamples.lastOrNull()?.t ?: 0.0)
        maxT = maxOf((recipe?.targetTime ?: 0.0) + 15, lastT + 5, currentTime ?: 0.0, 30.0)
        maxW = maxOf((recipe?.water ?: 0.0) * 1.08, (samples.maxOfOrNull { it.w } ?: 0.0) * 1.05, 10.0)

        // Flow axis: room for the recipe's range, scaled to the 98th percentile so one bump doesn't squash the graph.
        val sorted = flows.sorted()
        val typicalPeak = if (sorted.isEmpty()) 0.0 else sorted[min(sorted.size - 1, (sorted.size * 0.98).toInt())]
        val rawMax = min(max(max(recipe?.flowMax ?: 8.0, 4.0) * 1.3, typicalPeak * 1.1), 30.0)
        val step = listOf(1.0, 2.0, 2.5, 5.0, 10.0, 20.0).firstOrNull { it >= rawMax / 3 } ?: 20.0
        maxFlow = max(ceil(rawMax / step) * step, step)
        flowTicks = generateSequence(0.0) { it + step }.takeWhile { it <= maxFlow + 0.001 }.toList()

        val weightStep = niceStep(maxW / 4)
        weightTicks = generateSequence(0.0) { it + weightStep }.takeWhile { it <= maxW }.toList()

        // Downsample for drawing (≤ ~400 points), keeping the last sample.
        val stride = max(samples.size / 400, 1)
        val indices = (samples.indices step stride).toMutableList()
        if (samples.isNotEmpty() && indices.lastOrNull() != samples.lastIndex) indices.add(samples.lastIndex)
        weight = indices.map { samples[it].t to max(samples[it].w, 0.0) }
        flow = indices.map { samples[it].t to flows[it].coerceIn(0.0, maxFlow) }

        val pStride = max(pressureSamples.size / 400, 1)
        val pIndices = (pressureSamples.indices step pStride).toMutableList()
        if (pressureSamples.isNotEmpty() && pIndices.lastOrNull() != pressureSamples.lastIndex) pIndices.add(pressureSamples.lastIndex)
        pressure = pIndices.map { pressureSamples[it].t to pressureSamples[it].bar.coerceIn(0.0, maxPressure) }
    }

    companion object {
        fun niceStep(raw: Double): Double {
            if (raw <= 0) return 1.0
            val base = 10.0.pow(floor(log10(raw)))
            val f = raw / base
            val nice = when {
                f <= 1 -> 1.0
                f <= 2 -> 2.0
                f <= 2.5 -> 2.5
                f <= 5 -> 5.0
                else -> 10.0
            }
            return nice * base
        }
    }
}

/**
 * Weight (left axis) and flow in g/s (right axis) on one chart, with optional pressure profiling (bar).
 * Tap "Flow" in the legend to show or hide the flow overlay (remembered app-wide).
 */
@Composable
fun BrewChart(
    samples: List<WeightSample>,
    recipe: Recipe?,
    modifier: Modifier = Modifier,
    currentTime: Double? = null,
    height: Dp = 200.dp,
    showFlowRange: Boolean = false,
    pressureSamples: List<PressureSample> = emptyList(),
) {
    val container = LocalContainer.current
    val settings by container.settings.settings.collectAsStateWithLifecycle()
    val flowVisible = settings.chartShowsFlow
    val hasPressure = pressureSamples.isNotEmpty()
    val model = remember(samples, recipe, currentTime, pressureSamples) {
        ChartModel(samples, recipe, currentTime, pressureSamples)
    }
    val measurer = rememberTextMeasurer()
    val accent = MaterialTheme.colorScheme.primary
    val grid = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.15f)
    val labelColor = MaterialTheme.colorScheme.onSurfaceVariant
    val recipeColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f)

    Column(modifier) {
        Canvas(Modifier.fillMaxWidth().height(height)) {
            val labelStyle = TextStyle(fontSize = 10.sp, color = labelColor)
            val left = 30.dp.toPx()
            val right = if (flowVisible || hasPressure) 26.dp.toPx() else 6.dp.toPx()
            val top = 6.dp.toPx()
            val bottom = 18.dp.toPx()
            val x0 = left
            val x1 = size.width - right
            val y0 = top
            val y1 = size.height - bottom
            fun x(t: Double) = (x0 + (t / model.maxT) * (x1 - x0)).toFloat()
            fun yW(w: Double) = (y1 - (w / model.maxW) * (y1 - y0)).toFloat()
            fun yF(f: Double) = (y1 - (f / model.maxFlow) * (y1 - y0)).toFloat()
            fun yP(p: Double) = (y1 - (p / model.maxPressure) * (y1 - y0)).toFloat()

            // Weight grid + labels (left)
            model.weightTicks.forEach { w ->
                drawLine(grid, Offset(x0, yW(w)), Offset(x1, yW(w)), strokeWidth = 1f)
                val layout = measurer.measure(w.toInt().toString(), labelStyle)
                drawText(layout, topLeft = Offset(x0 - layout.size.width - 4.dp.toPx(), yW(w) - layout.size.height / 2f))
            }
            // Time grid + labels (bottom)
            val timeStep = if (model.maxT > 300) 60.0 else 30.0
            var t = 0.0
            while (t <= model.maxT) {
                drawLine(grid, Offset(x(t), y0), Offset(x(t), y1), strokeWidth = 1f)
                val layout = measurer.measure(t.mmss(), labelStyle)
                drawText(layout, topLeft = Offset(x(t) - layout.size.width / 2f, y1 + 3.dp.toPx()))
                t += timeStep
            }
            // Step markers
            model.stepTimes.forEach { time ->
                drawLine(grid, Offset(x(time), y0), Offset(x(time), y1), strokeWidth = 1.5f)
            }

            if (flowVisible) {
                if (showFlowRange && recipe != null) {
                    val yTop = yF(min(recipe.flowMax, model.maxFlow))
                    val yBottom = yF(min(recipe.flowMin, model.maxFlow))
                    drawRect(FlowTeal.copy(alpha = 0.08f), topLeft = Offset(x0, yTop), size = Size(x1 - x0, yBottom - yTop))
                }
                drawSeries(model.flow, ::x, ::yF, y1, FlowTeal, 1.5.dp.toPx(),
                    Brush.verticalGradient(listOf(FlowTeal.copy(alpha = 0.22f), FlowTeal.copy(alpha = 0.10f)), startY = y0, endY = y1))
                model.flowTicks.forEach { f ->
                    val layout = measurer.measure(flowLabel(f), labelStyle.copy(color = FlowTeal))
                    drawText(layout, topLeft = Offset(x1 + 4.dp.toPx(), yF(f) - layout.size.height / 2f))
                }
            }

            // Pressure curve (bar)
            if (hasPressure) {
                drawSeries(
                    model.pressure, ::x, ::yP, y1, PressureAmber, 2.dp.toPx(),
                    Brush.verticalGradient(listOf(PressureAmber.copy(alpha = 0.22f), PressureAmber.copy(alpha = 0.04f)), startY = y0, endY = y1)
                )
                if (!flowVisible) {
                    model.pressureTicks.forEach { p ->
                        val layout = measurer.measure("${p.toInt()} bar", labelStyle.copy(color = PressureAmber))
                        drawText(layout, topLeft = Offset(x1 + 4.dp.toPx(), yP(p) - layout.size.height / 2f))
                    }
                }
            }

            // Recipe curve (dashed)
            if (model.target.size > 1) {
                val path = Path()
                model.target.forEachIndexed { i, (time, w) -> if (i == 0) path.moveTo(x(time), yW(w)) else path.lineTo(x(time), yW(w)) }
                drawPath(path, recipeColor, style = Stroke(width = 2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(14f, 10f))))
            }

            // Weight
            drawSeries(model.weight, ::x, ::yW, y1, accent, 3.dp.toPx(),
                Brush.verticalGradient(listOf(accent.copy(alpha = if (flowVisible) 0.16f else 0.26f), accent.copy(alpha = 0.02f)), startY = y0, endY = y1))

            if (currentTime != null) {
                drawLine(accent.copy(alpha = 0.5f), Offset(x(currentTime), y0), Offset(x(currentTime), y1), strokeWidth = 1.5.dp.toPx(),
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 6f)))
            }
        }
        Spacer(Modifier.height(6.dp))
        Legend(hasRecipe = recipe != null, flowVisible = flowVisible, hasPressure = hasPressure, accent = accent, recipeColor = recipeColor) {
            container.settings.update { it.copy(chartShowsFlow = !it.chartShowsFlow) }
            container.haptics.tap()
        }
        if (flowVisible && showFlowRange && recipe != null) {
            Text(
                "Shaded band: the recipe's target pour rate (${flowLabel(recipe.flowMin)}–${flowLabel(recipe.flowMax)} g/s)",
                style = MaterialTheme.typography.labelSmall,
                color = labelColor.copy(alpha = 0.7f),
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}

private fun DrawScope.drawSeries(
    points: List<Pair<Double, Double>>,
    x: (Double) -> Float,
    y: (Double) -> Float,
    baseline: Float,
    color: Color,
    strokeWidth: Float,
    fill: Brush,
) {
    if (points.size < 2) return
    val line = Path()
    val area = Path()
    points.forEachIndexed { i, (t, v) ->
        if (i == 0) {
            line.moveTo(x(t), y(v))
            area.moveTo(x(t), baseline)
            area.lineTo(x(t), y(v))
        } else {
            line.lineTo(x(t), y(v))
            area.lineTo(x(t), y(v))
        }
    }
    area.lineTo(x(points.last().first), baseline)
    area.close()
    drawPath(area, fill)
    drawPath(line, color, style = Stroke(width = strokeWidth, cap = StrokeCap.Round, join = StrokeJoin.Round))
}

@Composable
private fun Legend(
    hasRecipe: Boolean,
    flowVisible: Boolean,
    hasPressure: Boolean,
    accent: Color,
    recipeColor: Color,
    onToggleFlow: () -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        LegendItem("Weight g") { Box(Modifier.width(14.dp).height(3.dp).clip(RoundedCornerShape(2.dp)).background(accent)) }
        if (hasRecipe) {
            Spacer(Modifier.width(14.dp))
            LegendItem("Recipe") {
                Canvas(Modifier.width(14.dp).height(3.dp)) {
                    drawLine(recipeColor, Offset(0f, size.height / 2), Offset(size.width, size.height / 2), strokeWidth = size.height,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 6f)))
                }
            }
        }
        if (hasPressure) {
            Spacer(Modifier.width(14.dp))
            LegendItem("Pressure bar") { Box(Modifier.width(14.dp).height(3.dp).clip(RoundedCornerShape(2.dp)).background(PressureAmber)) }
        }
        Spacer(Modifier.width(14.dp))
        Row(
            Modifier.clip(RoundedCornerShape(6.dp)).clickable(onClick = onToggleFlow).padding(2.dp).alpha(if (flowVisible) 1f else 0.45f),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            LegendItem("Flow g/s") {
                Box(
                    Modifier.size(14.dp, 8.dp).clip(RoundedCornerShape(2.dp))
                        .background(FlowTeal.copy(alpha = if (flowVisible) 0.5f else 0.15f))
                        .border(1.dp, FlowTeal, RoundedCornerShape(2.dp)),
                )
            }
        }
    }
}

@Composable
private fun LegendItem(title: String, swatch: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        swatch()
        Spacer(Modifier.width(5.dp))
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

fun flowLabel(value: Double): String = if (value == floor(value)) value.toInt().toString() else fmt1(value)
