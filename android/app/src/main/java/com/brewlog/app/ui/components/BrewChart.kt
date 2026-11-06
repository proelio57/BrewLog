package com.brewlog.app.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.brewlog.app.LocalContainer
import com.brewlog.app.domain.PressureSample
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.WeightSample

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
    PureBrewChart(
        samples = samples,
        recipe = recipe,
        modifier = modifier,
        currentTime = currentTime,
        height = height,
        showFlowRange = showFlowRange,
        flowVisible = settings.chartShowsFlow,
        hasPressure = pressureSamples.isNotEmpty(),
        pressureSamples = pressureSamples,
        onToggleFlow = {
            container.settings.update { it.copy(chartShowsFlow = !it.chartShowsFlow) }
            container.haptics.tap()
        }
    )
}
