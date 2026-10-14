package com.brewlog.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.CropFree
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.FilterAlt
import androidx.compose.material.icons.filled.Grain
import androidx.compose.material.icons.filled.HourglassBottom
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.Opacity
import androidx.compose.material.icons.filled.Scale
import androidx.compose.material.icons.filled.Spa
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.filled.Science
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.brewlog.app.analysis.FindingLevel
import com.brewlog.app.domain.BrewMethod
import com.brewlog.app.domain.StepKind
import com.brewlog.app.domain.TasteFeedback
import com.brewlog.app.domain.TasteProfile
import com.brewlog.app.ui.theme.GoodGreen
import com.brewlog.app.ui.theme.InfoBlue
import com.brewlog.app.ui.theme.StarOrange
import com.brewlog.app.ui.theme.WarnOrange

@Composable
fun BrewCard(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Surface(
        modifier = modifier.fillMaxWidth().let { if (onClick != null) it.clip(RoundedCornerShape(20.dp)).clickable(onClick = onClick) else it },
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(Modifier.padding(16.dp), content = content)
    }
}

@Composable
fun SectionHeader(title: String, trailing: String? = null) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            title.uppercase(),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            letterSpacing = 0.6.sp,
        )
        Spacer(Modifier.weight(1f))
        if (trailing != null) Text(trailing, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun RowScope.StatView(value: String, label: String, icon: ImageVector? = null) {
    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) {
                Icon(icon, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(3.dp))
            }
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun TasteProfileBars(profile: TasteProfile) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        TasteRow("Acidity", profile.acidity, Color(0xFFFFCC00))
        TasteRow("Sweetness", profile.sweetness, Color(0xFFFF9500))
        TasteRow("Body", profile.body, Color(0xFFA2845E))
        TasteRow("Clarity", profile.clarity, Color(0xFF30B0C7))
    }
}

@Composable
private fun TasteRow(label: String, value: Int, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.width(84.dp), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (i in 1..5) {
                Box(
                    Modifier.weight(1f).height(8.dp).clip(CircleShape)
                        .background(if (i <= value) color else MaterialTheme.colorScheme.surfaceVariant),
                )
            }
        }
    }
}

@Composable
fun StarRating(rating: Int, onChange: (Int) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        for (i in 1..5) {
            Icon(
                if (i <= rating) Icons.Filled.Star else Icons.Filled.StarBorder,
                contentDescription = "$i stars",
                tint = if (i <= rating) StarOrange else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                modifier = Modifier.size(34.dp).clip(CircleShape).clickable { onChange(if (rating == i) 0 else i) },
            )
        }
    }
}

@Composable
fun StarsLabel(rating: Int) {
    Row {
        for (i in 1..5) {
            Icon(
                if (i <= rating) Icons.Filled.Star else Icons.Filled.StarBorder, null,
                Modifier.size(11.dp),
                tint = if (i <= rating) StarOrange else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
            )
        }
    }
}

/** Pill-shaped toggle chip (like the iOS Chip). */
@Composable
fun PillChip(title: String, selected: Boolean, icon: ImageVector? = null, tint: Color = MaterialTheme.colorScheme.primary, onClick: () -> Unit) {
    val shape = RoundedCornerShape(50)
    Row(
        Modifier.clip(shape)
            .background(if (selected) tint.copy(alpha = 0.18f) else MaterialTheme.colorScheme.surfaceVariant)
            .border(1.5.dp, if (selected) tint else Color.Transparent, shape)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, Modifier.size(16.dp), tint = if (selected) tint else MaterialTheme.colorScheme.onSurface)
            Spacer(Modifier.width(6.dp))
        }
        Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium,
            color = if (selected) tint else MaterialTheme.colorScheme.onSurface)
    }
}

data class PickerOption(val id: String, val name: String)

/** "Title ……… Selection ⌃⌄" row with a dropdown. Long names truncate to one line. */
@Composable
fun MenuPickerRow(
    title: String,
    icon: ImageVector,
    options: List<PickerOption>,
    selectedId: String?,
    noneLabel: String = "None",
    onSelect: (String?) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(8.dp))
        Text(title, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.width(12.dp))
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            Row(
                Modifier.clip(RoundedCornerShape(8.dp)).clickable { expanded = true }.padding(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    options.firstOrNull { it.id == selectedId }?.name ?: noneLabel,
                    color = MaterialTheme.colorScheme.primary,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.End,
                    modifier = Modifier.weight(1f, fill = false),
                )
                Icon(Icons.Filled.UnfoldMore, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                DropdownMenuItem(text = { Text(noneLabel) }, onClick = { onSelect(null); expanded = false })
                options.forEach { option ->
                    DropdownMenuItem(text = { Text(option.name) }, onClick = { onSelect(option.id); expanded = false })
                }
            }
        }
    }
}

@Composable
fun MethodBadge(method: BrewMethod) {
    Text(
        method.displayName,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f))
            .padding(horizontal = 10.dp, vertical = 4.dp),
    )
}

@Composable
fun IconCircle(icon: ImageVector, tint: Color, size: Int = 40, background: Color = tint.copy(alpha = 0.15f)) {
    Box(Modifier.size(size.dp).clip(CircleShape).background(background), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = tint, modifier = Modifier.size((size * 0.5).dp))
    }
}

// Icon mapping (SF Symbols on iOS → Material icons)

val TasteFeedback.icon: ImageVector
    get() = when (this) {
        TasteFeedback.PERFECT -> Icons.Filled.Verified
        TasteFeedback.SOUR -> Icons.Filled.Science
        TasteFeedback.BITTER -> Icons.Filled.LocalFireDepartment
        TasteFeedback.WEAK -> Icons.Filled.Opacity
        TasteFeedback.STRONG -> Icons.Filled.Bolt
        TasteFeedback.ASTRINGENT -> Icons.Filled.Spa
        TasteFeedback.FLAT -> Icons.Filled.RemoveCircleOutline
    }

val StepKind.icon: ImageVector
    get() = when (this) {
        StepKind.BLOOM -> Icons.Filled.AutoAwesome
        StepKind.POUR -> Icons.Filled.WaterDrop
        StepKind.SWIRL -> Icons.Filled.Autorenew
        StepKind.STIR -> Icons.Filled.Air
        StepKind.CLOSE_VALVE -> Icons.Filled.Lock
        StepKind.OPEN_VALVE -> Icons.Filled.LockOpen
        StepKind.REMOVE -> Icons.Filled.ArrowUpward
    }

val FindingLevel.icon: ImageVector
    get() = when (this) {
        FindingLevel.GOOD -> Icons.Filled.CheckCircle
        FindingLevel.INFO -> Icons.Filled.Info
        FindingLevel.WARNING -> Icons.Filled.Warning
    }

val FindingLevel.color: Color
    get() = when (this) {
        FindingLevel.GOOD -> GoodGreen
        FindingLevel.INFO -> InfoBlue
        FindingLevel.WARNING -> WarnOrange
    }

fun suggestionIcon(key: String): ImageVector = when {
    key == "grind" -> Icons.Filled.Tune
    key.startsWith("temp") -> Icons.Filled.Thermostat
    key == "bloom" -> Icons.Filled.AutoAwesome
    key.startsWith("ratio") || key == "dose-up" -> Icons.Filled.WaterDrop
    key == "evenness" || key == "walls" -> Icons.Filled.CropFree
    key == "fines" -> Icons.Filled.Grain
    key.startsWith("filter") -> Icons.Filled.FilterAlt
    key == "drawdown" -> Icons.Filled.HourglassBottom
    key == "rest" || key == "fresh" -> Icons.Filled.CalendarToday
    key.startsWith("steep") -> Icons.Filled.Timer
    key == "history" || key == "repeat" -> Icons.Filled.Star
    key == "agitation-up" -> Icons.Filled.Autorenew
    key == "gentle" || key == "rinse" || key == "water" -> Icons.Filled.Opacity
    key == "clarity" -> Icons.AutoMirrored.Filled.ShowChart
    else -> Icons.Filled.Coffee
}

val ScaleIcon: ImageVector get() = Icons.Filled.Scale
val FilterIcon: ImageVector get() = Icons.Filled.Description
