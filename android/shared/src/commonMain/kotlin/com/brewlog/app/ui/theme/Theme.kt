package com.brewlog.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Same palette as the iOS app (AccentColor asset + iOS grouped backgrounds).
val Accent = Color(0xFFB86D3C)
val AccentDark = Color(0xFFE29961)
val FlowTeal = Color(0xFF30B0C7)
val GoodGreen = Color(0xFF34C759)
val WarnOrange = Color(0xFFFF9500)
val InfoBlue = Color(0xFF007AFF)
val StarOrange = Color(0xFFFF9500)

private val LightColors = lightColorScheme(
    primary = Accent,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFF5E6DC),
    onPrimaryContainer = Color(0xFF5A2E10),
    secondary = FlowTeal,
    background = Color(0xFFF2F2F7),
    onBackground = Color(0xFF000000),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF000000),
    surfaceVariant = Color(0xFFE9E9EE),
    onSurfaceVariant = Color(0xFF6C6C70),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFFFFFFF),
    surfaceContainer = Color(0xFFF2F2F7),
    outlineVariant = Color(0xFFE0E0E5),
)

private val DarkColors = darkColorScheme(
    primary = AccentDark,
    onPrimary = Color(0xFF2B1608),
    primaryContainer = Color(0xFF4A2A14),
    onPrimaryContainer = Color(0xFFF5D2B8),
    secondary = FlowTeal,
    background = Color(0xFF000000),
    onBackground = Color(0xFFFFFFFF),
    surface = Color(0xFF1C1C1E),
    onSurface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFF2C2C2E),
    onSurfaceVariant = Color(0xFF98989F),
    surfaceContainerLowest = Color(0xFF1C1C1E),
    surfaceContainerLow = Color(0xFF1C1C1E),
    surfaceContainer = Color(0xFF000000),
    outlineVariant = Color(0xFF38383A),
)

@Composable
fun BrewLogTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors, content = content)
}
