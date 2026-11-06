@file:OptIn(ExperimentalMaterial3Api::class)

package com.brewlog.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Scale
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.brewlog.app.BrewConfig
import com.brewlog.app.LocalContainer
import com.brewlog.app.analysis.GrindRecommendation
import com.brewlog.app.analysis.GrindRecommender
import com.brewlog.app.brewing.BrewSession
import com.brewlog.app.brewing.ShotMonitor
import com.brewlog.app.data.BrewSetupState
import com.brewlog.app.domain.BrewMethod
import com.brewlog.app.domain.Equipment
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.domain.GrinderSpec
import com.brewlog.app.domain.GrindConverter
import com.brewlog.app.domain.grams
import com.brewlog.app.domain.grams1
import com.brewlog.app.domain.roundHalfAway
import com.brewlog.app.machine.MachineConnection
import com.brewlog.app.machine.MachineKind
import com.brewlog.app.machine.MachineManager
import com.brewlog.app.ui.Routes
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.CapsuleOption
import com.brewlog.app.ui.components.CapsuleSwitch
import com.brewlog.app.ui.components.FilterIcon
import com.brewlog.app.ui.components.MenuPickerRow
import com.brewlog.app.ui.components.MethodBadge
import com.brewlog.app.ui.components.PickerOption
import com.brewlog.app.ui.components.ScaleIcon
import com.brewlog.app.ui.components.SectionHeader
import com.brewlog.app.ui.components.StatView
import com.brewlog.app.ui.components.TasteProfileBars
import com.brewlog.app.ui.theme.GoodGreen
import com.brewlog.app.ui.theme.WarnOrange
import kotlin.math.max

private val tabular = TextStyle(fontFeatureSettings = "tnum")

@Composable
fun BrewSetupScreen(nav: NavHostController) {
    val container = LocalContainer.current
    val mode = container.brewMode
    val isEspresso = mode == "espresso"
    val setup = if (isEspresso) container.espressoSetup else container.setup
    val data by container.repository.data.collectAsStateWithLifecycle()
    val settings by container.settings.settings.collectAsStateWithLifecycle()
    val ready by container.scale.ready.collectAsStateWithLifecycle()
    val scaleWeight by container.scale.weight.collectAsStateWithLifecycle()
    val pressureReady by container.pressure.ready.collectAsStateWithLifecycle()
    val pressureBar by container.pressure.pressure.collectAsStateWithLifecycle()
    val pressureState by container.pressure.state.collectAsStateWithLifecycle()
    var showScale by rememberSaveable { mutableStateOf(false) }
    var showPressure by rememberSaveable { mutableStateOf(false) }
    var showProfiles by rememberSaveable { mutableStateOf(false) }

    val beans = data.beans.filter { !it.isArchived }.sortedByDescending { it.createdAt }
    val brewers = data.equipment.filter { it.type == EquipmentType.BREWER && (it.method == BrewMethod.ESPRESSO) == isEspresso }.sortedBy { it.name }
    val grinders = data.equipment.filter { it.type == EquipmentType.GRINDER }.sortedBy { it.name }
    val filters = data.equipment.filter { it.type == EquipmentType.FILTER }.sortedBy { it.name }
    val selectedGrinder = grinders.firstOrNull { it.id == setup.grinderId }
    val waters = data.equipment.filter { it.type == EquipmentType.WATER }.sortedBy { it.name }
    val selectedBean = beans.firstOrNull { it.id == setup.beanId }
    val recommendation = GrindRecommender.recommend(setup.beanId, selectedGrinder, setup.recipe.id, data.brews)

    LaunchedEffect(brewers.map { it.id }) { setup.reconcileGear(EquipmentType.BREWER, brewers.map { it.id }) }
    LaunchedEffect(grinders.map { it.id }) { setup.reconcileGear(EquipmentType.GRINDER, grinders.map { it.id }, grinders, data.brews) }
    if (!isEspresso) {
        LaunchedEffect(filters.map { it.id }) { setup.reconcileGear(EquipmentType.FILTER, filters.map { it.id }) }
    }

    // Apply the history-based grind when bean, grinder or recipe change (unless the grind was set explicitly).
    val recommendationKey = "${setup.beanId}|${setup.grinderId}|${setup.recipe.id}"
    LaunchedEffect(recommendationKey, recommendation) {
        if (setup.lastRecommendationContext != recommendationKey || setup.grindValue == null) {
            setup.lastRecommendationContext = recommendationKey
            if (!setup.isGrindPinned) {
                if (recommendation != null) {
                    setup.grindValue = recommendation.value
                } else if (setup.grindValue == null && selectedGrinder != null) {
                    setup.grindValue = setup.lastGrindFor(selectedGrinder.id) ?: selectedGrinder.grinder.defaultStartingValue()
                }
            }
        }
    }

    BrewScreen(
        titleContent = {
            CapsuleSwitch(
                options = listOf(
                    CapsuleOption("filter", "Filter", Icons.Filled.WaterDrop),
                    CapsuleOption("espresso", "Espresso", Icons.Filled.Coffee),
                ),
                selection = mode,
                onSelectionChanged = { container.brewMode = it },
            )
        },
        actions = {
            IconButton(onClick = { nav.navigate(Routes.WEIGH) }) { Icon(Icons.Filled.Scale, contentDescription = "Quick weigh") }
            IconButton(onClick = { nav.navigate(Routes.SETTINGS) }) { Icon(Icons.Filled.Settings, contentDescription = "Settings") }
        },
        bottomBar = {
            Box(Modifier.background(MaterialTheme.colorScheme.background).padding(horizontal = 16.dp, vertical = 8.dp)) {
                PrimaryButton(if (ready) "Start brew" else "Start brew (timer only)", if (ready) Icons.Filled.Scale else Icons.Filled.Timer) {
                    val config = BrewConfig(
                        recipe = setup.scaledRecipe,
                        dose = setup.dose,
                        waterTemp = setup.waterTemp,
                        beanId = selectedBean?.id,
                        brewer = brewers.firstOrNull { it.id == setup.brewerId },
                        grinder = selectedGrinder,
                        filter = if (isEspresso) null else filters.firstOrNull { it.id == setup.filterId },
                        grindValue = if (selectedGrinder == null) null else setup.grindValue,
                        grindText = setup.grindText,
                        water = waters.firstOrNull { it.id == setup.waterId },
                    )
                    container.activeBrew = config to BrewSession(
                        config.recipe, container.scale, { container.settings.current }, container::cue,
                        machine = container.machine,
                        monitorReady = { container.pressure.ready.value },
                        prepareMonitor = { container.pressure.prepareForBrew(it) },
                        onSpeak = { container.voice.say(it) },
                    )
                    nav.navigate(Routes.LIVE)
                }
            }
        },
    ) { padding ->
        CardList(padding) {
            if (data.equipment.isEmpty() && !settings.setupBannerDismissed) {
                item { SetupBanner(onStart = { nav.navigate(Routes.ONBOARDING) }, onDismiss = { container.settings.update { it.copy(setupBannerDismissed = true) } }) }
            }
            if (isEspresso) {
                item {
                    DeviceStrip(
                        scaleReady = ready,
                        scaleWeight = scaleWeight,
                        machine = container.machine,
                        pressureReady = pressureReady,
                        pressureBar = pressureBar,
                        pressureEnabled = settings.espressoPressureEnabled,
                        pressureLabel = pressureState.label,
                        onOpenScale = { showScale = true },
                        onOpenSettings = { nav.navigate(Routes.SETTINGS) },
                        onOpenPressure = { showPressure = true },
                    )
                }
                item { EspressoSetupCard(setup = setup, machine = container.machine, onOpenProfiles = { showProfiles = true }) }
                item { MachineCard(setup.scaledRecipe, setup.dose, setup.waterTemp) { nav.navigate(Routes.SETTINGS) } }
            } else {
                item { ScaleStatusCard { showScale = true } }
                if (settings.espressoPressureEnabled) {
                    item { PressureStatusCard { showPressure = true } }
                }
                item { DoseCard(setup = setup) }
            }
            item {
                SectionHeader("Coffee")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        selectedBean?.let {
                            com.brewlog.app.ui.components.BeanThumbnail(it.id, it.roastLevel, size = 36.dp)
                            Spacer(Modifier.width(10.dp))
                        }
                        Box(Modifier.weight(1f)) {
                            MenuPickerRow("Beans", Icons.Filled.Eco, beans.map { PickerOption(it.id, it.displayName) }, setup.beanId) { setup.beanId = it }
                        }
                        IconButton(onClick = { nav.navigate(Routes.bean(Routes.NEW)) }) {
                            Icon(Icons.Filled.AddCircle, contentDescription = "Add beans", tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                    Text(
                        selectedBean?.let { bean ->
                            listOfNotNull(bean.roastLevel.displayName, bean.daysOffRoast()?.let { "$it d off roast" }, bean.remaining.grams() + " left")
                                .joinToString(" · ")
                        } ?: "Optional. You can also add the beans after brewing.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            item {
                SectionHeader("Gear & grind")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    GearRow(if (isEspresso) "Machine" else "Brewer", Icons.Filled.Coffee, brewers, setup.brewerId, { setup.brewerId = it }) { nav.navigate(Routes.PRESETS) }
                    HorizontalDivider(Modifier.padding(vertical = 10.dp))
                    if (!isEspresso) {
                        GearRow("Filter", FilterIcon, filters, setup.filterId, { setup.filterId = it }) { nav.navigate(Routes.PRESETS) }
                        filters.firstOrNull { it.id == setup.filterId }?.subtitle?.takeIf { it.isNotEmpty() }?.let {
                            Text(it, Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.End)
                        }
                        HorizontalDivider(Modifier.padding(vertical = 10.dp))
                    }
                    GearRow("Grinder", Icons.Filled.Build, grinders, setup.grinderId, onSelect = { id ->
                        val g = grinders.firstOrNull { it.id == id }
                        setup.selectGrinder(id, g, data.brews)
                    }, onAdd = { nav.navigate(Routes.PRESETS) })
                    Spacer(Modifier.height(10.dp))
                    GrindInput(selectedGrinder?.grinder, setup.grindValue, { setup.setGrind(it) }, setup.grindText, { setup.grindText = it }, recommendation)
                    selectedGrinder?.let { g -> GrindConverter.hint(setup.recipe.grind, GrindConverter.calibrated(g.grinder, g.name)) }?.let { hint ->
                        Text("Recipe: $hint on your ${selectedGrinder.name}", Modifier.fillMaxWidth().padding(top = 6.dp),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.End)
                    }
                    if (waters.isNotEmpty()) {
                        HorizontalDivider(Modifier.padding(vertical = 10.dp))
                        GearRow("Water", Icons.Filled.WaterDrop, waters, setup.waterId, { setup.waterId = it }) { nav.navigate(Routes.TOOLS_WATER) }
                    }
                }
            }
            item {
                SectionHeader("Before you brew")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                container.settings.update { it.copy(weighBeansFirst = !settings.weighBeansFirst) }
                            }
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text("Weigh the beans", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                            Text(
                                if (ready) "On the scale, before the brewer goes on" else "With a scale connected",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = settings.weighBeansFirst,
                            onCheckedChange = { v -> container.settings.update { it.copy(weighBeansFirst = v) } },
                        )
                    }
                    if (!isEspresso) {
                        HorizontalDivider(Modifier.padding(vertical = 8.dp))
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    container.settings.update { it.copy(rinsePaper = !settings.rinsePaper) }
                                }
                                .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text("Rinse the paper", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                                Text("With hot water, then discard it", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Switch(
                                checked = settings.rinsePaper,
                                onCheckedChange = { v -> container.settings.update { it.copy(rinsePaper = v) } },
                            )
                        }
                    }
                }
            }
            // Last: the recipe is set once and rarely changed.
            item {
                SectionHeader("Recipe")
                Spacer(Modifier.height(8.dp))
                RecipeCard(setup = setup, onClick = { nav.navigate(Routes.RECIPE_PICKER) })
            }
        }
    }
    if (showScale) ScaleSheet { showScale = false }
    if (showPressure) PressureMonitorSheet { showPressure = false }
    if (showProfiles) MachineProfilesSheet { showProfiles = false }
}

@Composable
fun DeviceStrip(
    scaleReady: Boolean,
    scaleWeight: Double,
    machine: MachineManager,
    pressureReady: Boolean,
    pressureBar: Double,
    pressureEnabled: Boolean,
    pressureLabel: String,
    onOpenScale: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenPressure: () -> Unit,
) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        // Scale tile
        DeviceTile(
            name = "Scale",
            icon = ScaleIcon,
            live = scaleReady,
            value = if (scaleReady) scaleWeight.grams1() else "Connect",
            onClick = onOpenScale,
            modifier = Modifier.weight(1f),
        )

        // Machine tile
        val machineState by machine.state.collectAsStateWithLifecycle()
        val isMachineConnected = machineState.connection == MachineConnection.CONNECTED
        val machineValue = when (machineState.connection) {
            MachineConnection.OFF -> if (machine.kind == MachineKind.NONE) "Set up" else "Off"
            MachineConnection.CONNECTING -> "Connecting"
            MachineConnection.UNREACHABLE -> "Offline"
            MachineConnection.CONNECTED -> machineState.status.temperature?.let { "${it.toInt()} °C" } ?: "Connected"
        }
        DeviceTile(
            name = if (machine.kind == MachineKind.NONE) "Machine" else machine.displayName,
            icon = Icons.Filled.Coffee,
            live = isMachineConnected,
            value = machineValue,
            onClick = onOpenSettings,
            modifier = Modifier.weight(1f),
        )

        // Pressure tile
        if (machine.readsPressure) {
            val p = if (isMachineConnected) machineState.status.pressure else null
            DeviceTile(
                name = "Pressure",
                icon = Icons.Filled.Speed,
                live = p != null,
                value = p?.let { String.format(java.util.Locale.US, "%.1f bar", it) } ?: "–",
                onClick = onOpenSettings,
                modifier = Modifier.weight(1f),
            )
        } else {
            DeviceTile(
                name = "Pressure",
                icon = Icons.Filled.Speed,
                live = pressureReady,
                value = if (pressureReady) String.format(java.util.Locale.US, "%.1f bar", pressureBar)
                        else if (pressureEnabled) pressureLabel else "Off",
                onClick = onOpenPressure,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun DeviceTile(
    name: String,
    icon: ImageVector,
    live: Boolean,
    value: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.clip(RoundedCornerShape(16.dp)).clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    icon,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = if (live) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.width(4.dp))
                Box(
                    Modifier.size(6.dp).clip(CircleShape).background(
                        if (live) GoodGreen else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                    ),
                )
            }
            Text(name, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            Text(value, style = MaterialTheme.typography.bodyMedium.merge(tabular), fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    }
}

@Composable
fun EspressoSetupCard(
    setup: BrewSetupState,
    machine: MachineManager,
    onOpenProfiles: () -> Unit = {},
) {
    val recipe = setup.scaledRecipe
    val machineTemp = if (machine.isConnected) {
        val t = machine.status.targetTemperature
        if (t != null && t in 70.0..105.0) t else null
    } else null
    val targetPressure = ShotMonitor.targetPressure(
        recipe = recipe.pressure,
        machineTarget = if (machine.isConnected) machine.status.targetPressure else null,
    )
    val displayTemp = (machineTemp ?: setup.waterTemp).toInt()

    BrewCard {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            StatView(setup.dose.grams1(), "Dose", Icons.Filled.Scale)
            StatView(recipe.water.grams(), "Yield", Icons.Filled.WaterDrop)
            StatView(recipe.ratioText, "Ratio")
            StatView("$displayTemp°", "Temp", Icons.Filled.Thermostat)
        }
        HorizontalDivider(Modifier.padding(vertical = 12.dp))
        StepperRow("Dose", setup.dose.grams1(), Icons.Filled.Scale,
            onMinus = { setup.dose = maxOf(5.0, setup.dose - 0.5) },
            onPlus = { setup.dose = minOf(30.0, setup.dose + 0.5) },
        )
        if (machine.isConnected) {
            Spacer(Modifier.height(8.dp))
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Thermostat, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Temperature", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.weight(1f))
                Text(machineTemp?.let { "${it.toInt()} °C" } ?: "–", fontWeight = FontWeight.SemiBold)
            }
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Speed, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Pressure", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.weight(1f))
                Text(targetPressure?.let { String.format(java.util.Locale.US, "%.1f bar", it) } ?: "–", fontWeight = FontWeight.SemiBold)
            }
            Row(
                Modifier.fillMaxWidth().padding(vertical = 4.dp).let {
                    if (machine.canChooseProfile) it.clickable(onClick = onOpenProfiles) else it
                },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Tune, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Profile", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.weight(1f))
                Text(machine.status.profile ?: "–", fontWeight = FontWeight.SemiBold)
                if (machine.canChooseProfile) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                }
            }
            Text("from ${machine.displayName}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.End)
        } else {
            StepperRow("Brew temperature", "${setup.waterTemp.toInt()} °C", Icons.Filled.Thermostat,
                onMinus = { setup.waterTemp = maxOf(70.0, setup.waterTemp - 1.0) },
                onPlus = { setup.waterTemp = minOf(100.0, setup.waterTemp + 1.0) },
            )
        }
        Spacer(Modifier.height(4.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Tune, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Grind", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
            Text(setup.recipe.grind, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.End)
        }
    }
}

@Composable
private fun SetupBanner(onStart: () -> Unit, onDismiss: () -> Unit) {
    BrewCard {
        Row(verticalAlignment = Alignment.Top) {
            Icon(Icons.Filled.AutoAwesome, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text("Set up your gear", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text("Add your brewer, filter and grinder in about a minute so tips can be precise.",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                Button(onClick = onStart) { Text("Start setup") }
            }
            IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, contentDescription = "Dismiss", modifier = Modifier.size(18.dp)) }
        }
    }
}

@Composable
private fun RecipeCard(setup: BrewSetupState, onClick: () -> Unit) {
    val recipe = setup.recipe
    BrewCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(recipe.name, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text(recipe.author, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            MethodBadge(recipe.method)
        }
        Spacer(Modifier.height(10.dp))
        Text(recipe.tasteNotes, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 3)
        Spacer(Modifier.height(12.dp))
        TasteProfileBars(recipe.taste)
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Change recipe", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.primary)
        }
    }
}

@Composable
private fun DoseCard(setup: BrewSetupState) {
    val recipe = setup.scaledRecipe
    BrewCard {
        Row {
            StatView(setup.dose.grams1(), "Coffee")
            StatView(recipe.water.grams(), if (recipe.isEspresso) "Yield" else "Water", Icons.Filled.WaterDrop)
            StatView(recipe.ratioText, "Ratio")
            StatView("${setup.waterTemp.toInt()}°", "Temp", Icons.Filled.Thermostat)
        }
        HorizontalDivider(Modifier.padding(vertical = 12.dp))
        StepperRow("Coffee dose", setup.dose.grams1(), Icons.Filled.Scale,
            onMinus = { setup.dose = max(5.0, setup.dose - 0.5) }, onPlus = { setup.dose = minOf(60.0, setup.dose + 0.5) })
        Spacer(Modifier.height(8.dp))
        StepperRow(if (recipe.isEspresso) "Brew temperature" else "Water temperature", "${setup.waterTemp.toInt()} °C", Icons.Filled.Thermostat,
            onMinus = { setup.waterTemp = max(70.0, setup.waterTemp - 1) }, onPlus = { setup.waterTemp = minOf(100.0, setup.waterTemp + 1) })
        Spacer(Modifier.height(10.dp))
        Row {
            Icon(Icons.Filled.Tune, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Grind", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
            Spacer(Modifier.width(12.dp))
            Text(setup.recipe.grind, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.End)
        }
    }
}

@Composable
private fun GearRow(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, items: List<Equipment>,
                    selectedId: String?, onSelect: (String?) -> Unit, onAdd: () -> Unit) {
    if (items.isEmpty()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(title, Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick = onAdd) { Text("Add ${title.lowercase()}") }
        }
    } else {
        MenuPickerRow(title, icon, items.map { PickerOption(it.id, it.name) }, selectedId, onSelect = onSelect)
    }
}

/** Grind entry on the grinder's own scale, with finer/coarser buttons and a history-based suggestion. */
@Composable
fun GrindInput(
    spec: GrinderSpec?,
    value: Double?,
    onValue: (Double?) -> Unit,
    text: String,
    onText: (String) -> Unit,
    recommendation: GrindRecommendation?,
) {
    if (spec == null) {
        OutlinedTextField(text, onValueChange = { onText(it.take(80)) }, label = { Text("Grind setting (e.g. medium-fine)") },
            singleLine = true, modifier = Modifier.fillMaxWidth())
        Text("Add your grinder in Gear to track exact settings and get click-by-click suggestions.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        return
    }
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            GrindStepButton("Finer", Icons.Filled.Remove) { onValue(step(value ?: recommendation?.value ?: 0.0, spec, coarser = false)) }
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                GrindValueField(value, onValue, decimals = if (spec.step < 1) 2 else 0)
                Text(spec.unit.suffix.ifEmpty { spec.unit.displayName.lowercase() }, style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            GrindStepButton("Coarser", Icons.Filled.Add) { onValue(step(value ?: recommendation?.value ?: 0.0, spec, coarser = true)) }
        }
        if (recommendation != null && recommendation.value != value) {
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.1f))
                    .clickable { onValue(recommendation.value) }.padding(10.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Icon(Icons.Filled.AutoAwesome, null, tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Column {
                    Text("Use ${spec.format(recommendation.value)}", fontWeight = FontWeight.SemiBold)
                    Text(recommendation.reason, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        } else if (recommendation != null) {
            Text("✓ ${recommendation.reason}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (spec.rangeNote.isNotEmpty()) {
            Text("Typical pour-over range: ${spec.rangeNote}", style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f))
        }
    }
}

private fun step(base: Double, spec: GrinderSpec, coarser: Boolean): Double {
    val delta = if (coarser == spec.finerIsLower) spec.step else -spec.step
    return max(0.0, roundHalfAway((base + delta) / spec.step) * spec.step)
}

@Composable
private fun GrindStepButton(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Column(
        Modifier.clip(RoundedCornerShape(12.dp)).clickable(onClick = onClick).padding(4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.size(48.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, contentDescription = label) }
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun QuickAction(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Column(
        Modifier.clip(RoundedCornerShape(12.dp)).clickable(onClick = onClick).padding(4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.size(48.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, contentDescription = label) }
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Large centred number field (accepts "," and "."). */
@Composable
fun GrindValueField(value: Double?, onValue: (Double?) -> Unit, decimals: Int) {
    var text by remember { mutableStateOf(value?.let { formatNumber(it, decimals) } ?: "") }
    LaunchedEffect(value) {
        if (parseNumber(text) != value) text = value?.let { formatNumber(it, decimals) } ?: ""
    }
    BasicTextField(
        value = text,
        onValueChange = { input ->
            text = input.filter { it.isDigit() || it == '.' || it == ',' }.take(7)
            onValue(parseNumber(text)?.coerceIn(0.0, 10_000.0))
        },
        singleLine = true,
        textStyle = TextStyle(fontSize = 40.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurface),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        modifier = Modifier.widthIn(min = 80.dp, max = 160.dp),
        decorationBox = { inner ->
            Box(contentAlignment = Alignment.Center) {
                if (text.isEmpty()) Text("–", fontSize = 40.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                inner()
            }
        },
    )
}
