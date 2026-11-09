package com.brewlog.app.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.brewlog.app.analysis.PressureFocus
import com.brewlog.app.analysis.PressureZone
import com.brewlog.app.domain.PressureSample
import com.brewlog.app.ui.theme.Accent

/** Colours of the pressure relative to the target (same as iOS): below blue, on target green, above red. */
fun PressureZone.color(): Color = when (this) {
    PressureZone.LOW -> Color(0xFF0A84FF)
    PressureZone.ON_TARGET -> Color(0xFF34C759)
    PressureZone.HIGH -> Color(0xFFFF3B30)
    PressureZone.NO_TARGET -> Accent
}

/**
 * The pressure of a shot on a 0–12 bar axis. With [emphasis] (Settings → Pressure view, for setting the pressure by
 * hand): a thick line, the target as a green band of ± [PressureFocus.TOLERANCE] with a solid line, a label for every
 * bar and the latest reading as a dot in its zone colour. Without it the target is a plain line.
 */
@Composable
fun PressureChart(
    samples: List<PressureSample>,
    targetPressure: Double?,
    modifier: Modifier = Modifier,
    currentTime: Double? = null,
    height: Dp = 140.dp,
    emphasis: Boolean = false,
) {
    val maxBar = 12.0
    val maxT = maxOf(samples.lastOrNull()?.t ?: 0.0, currentTime ?: 0.0, 25.0) + 2
    val grid = MaterialTheme.colorScheme.outlineVariant
    val labels = if (emphasis) (12 downTo 0).toList() else listOf(12, 9, 6, 3, 0)
    Column(modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().height(height)) {
            Column(
                Modifier.width(22.dp).fillMaxHeight(),
                verticalArrangement = Arrangement.SpaceBetween,
                horizontalAlignment = Alignment.End,
            ) {
                labels.forEach {
                    Text("$it", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.End, modifier = Modifier.padding(end = 4.dp))
                }
            }
            Canvas(Modifier.weight(1f).fillMaxHeight().padding(vertical = 6.dp)) {
                fun x(t: Double) = (t / maxT * size.width).toFloat()
                fun y(p: Double) = (size.height - (p.coerceIn(0.0, maxBar) / maxBar) * size.height).toFloat()
                for (bar in 0..12 step 3) {
                    drawLine(grid, Offset(0f, y(bar.toDouble())), Offset(size.width, y(bar.toDouble())), strokeWidth = 1f)
                }
                if (targetPressure != null && targetPressure > 0) {
                    if (emphasis) {
                        val top = y(targetPressure + PressureFocus.TOLERANCE)
                        val bottom = y(targetPressure - PressureFocus.TOLERANCE)
                        drawRect(Color(0xFF34C759).copy(alpha = 0.18f), Offset(0f, top), Size(size.width, bottom - top))
                        drawLine(Color(0xFF34C759), Offset(0f, y(targetPressure)), Offset(size.width, y(targetPressure)), strokeWidth = 1.5.dp.toPx())
                    } else {
                        drawLine(Accent.copy(alpha = 0.6f), Offset(0f, y(targetPressure)), Offset(size.width, y(targetPressure)), strokeWidth = 1.dp.toPx())
                    }
                }
                if (samples.size >= 2) {
                    val path = Path()
                    samples.forEachIndexed { i, s -> if (i == 0) path.moveTo(x(s.t), y(s.bar)) else path.lineTo(x(s.t), y(s.bar)) }
                    drawPath(path, Accent, style = Stroke(width = (if (emphasis) 3 else 2).dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
                }
                val last = samples.lastOrNull()
                if (emphasis && last != null) {
                    drawCircle(PressureFocus.zone(last.bar, targetPressure).color(), radius = 6.dp.toPx(), center = Offset(x(last.t), y(last.bar)))
                }
            }
        }
        Text("Pressure (bar)", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 22.dp, top = 2.dp))
    }
}
