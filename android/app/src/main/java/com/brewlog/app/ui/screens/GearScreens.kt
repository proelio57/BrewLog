@file:OptIn(ExperimentalLayoutApi::class)

package com.brewlog.app.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Scale
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.brewlog.app.BuildConfig
import com.brewlog.app.LocalContainer
import com.brewlog.app.brewing.BrewCue
import com.brewlog.app.domain.BrewMethod
import com.brewlog.app.domain.Equipment
import com.brewlog.app.domain.EquipmentPreset
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.domain.FilterFlow
import com.brewlog.app.domain.GrindUnit
import com.brewlog.app.domain.GrinderSpec
import com.brewlog.app.domain.InputLimits
import com.brewlog.app.domain.PingLeadMode
import com.brewlog.app.domain.RoastLevel
import com.brewlog.app.domain.clamped
import com.brewlog.app.domain.fmt1
import com.brewlog.app.domain.sanitized
import com.brewlog.app.ui.Routes
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.FilterIcon
import com.brewlog.app.ui.components.PillChip
import com.brewlog.app.ui.components.SectionHeader
import com.brewlog.app.ui.theme.GoodGreen
import com.brewlog.app.ui.theme.WarnOrange
import kotlinx.coroutines.launch

fun EquipmentType.icon(): ImageVector = when (this) {
    EquipmentType.BREWER -> Icons.Filled.Coffee
    EquipmentType.GRINDER -> Icons.Filled.Tune
    EquipmentType.KETTLE -> Icons.Filled.LocalFireDepartment
    EquipmentType.FILTER -> FilterIcon
    EquipmentType.SCALE -> Icons.Filled.Scale
    EquipmentType.WATER -> Icons.Filled.WaterDrop
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun GearScreen(nav: NavHostController) {
    val container = LocalContainer.current
    val data by container.repository.data.collectAsStateWithLifecycle()
    var toDelete by remember { mutableStateOf<Equipment?>(null) }

    BrewScreen(title = "Gear") { padding ->
        CardList(padding) {
            item {
                BrewCard {
                    LinkRow("Setup assistant", Icons.Filled.AutoAwesome) { nav.navigate(Routes.ONBOARDING) }
                    HorizontalDivider(Modifier.padding(vertical = 6.dp))
                    LinkRow("Settings", Icons.Filled.Settings) { nav.navigate(Routes.SETTINGS) }
                }
            }
            EquipmentType.entries.forEach { type ->
                val items = data.equipment.filter { it.type == type }.sortedBy { it.name }
                if (items.isNotEmpty()) {
                    item { SectionHeader(type.displayName) }
                    items(items, key = { it.id }) { item ->
                        BrewCard {
                            Row(
                                Modifier.fillMaxWidth().combinedClickable(
                                    onClick = { nav.navigate(Routes.equipment(item.id)) },
                                    onLongClick = { toDelete = item },
                                ),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(type.icon(), null, tint = MaterialTheme.colorScheme.primary)
                                Spacer(Modifier.width(12.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(item.name, fontWeight = FontWeight.Medium)
                                    if (item.subtitle.isNotEmpty()) {
                                        Text(item.subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            item {
                BrewCard {
                    LinkRow("Add from presets", Icons.Filled.ViewModule) { nav.navigate(Routes.PRESETS) }
                    HorizontalDivider(Modifier.padding(vertical = 6.dp))
                    LinkRow("Add custom gear", Icons.Filled.AddCircleOutline) { nav.navigate(Routes.equipment(Routes.NEW)) }
                }
                Text("Your grinder's scale (clicks, numbers, dial) lets BrewLog suggest exact grind changes. Filter flow speed and roast " +
                    "suitability are used in the analysis. Long-press an item to delete it.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(4.dp))
            }
        }
    }

    toDelete?.let { item ->
        AlertDialog(
            onDismissRequest = { toDelete = null },
            title = { Text("Delete ${item.name}?") },
            confirmButton = {
                TextButton(onClick = { container.repository.deleteEquipment(item.id); toDelete = null }) { Text("Delete", color = Color(0xFFFF3B30)) }
            },
            dismissButton = { TextButton(onClick = { toDelete = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun LinkRow(title: String, icon: ImageVector, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.width(12.dp))
        Text(title, fontWeight = FontWeight.Medium)
    }
}

@Composable
fun PresetPickerScreen(nav: NavHostController) {
    val container = LocalContainer.current
    val data by container.repository.data.collectAsStateWithLifecycle()
    var search by rememberSaveable { mutableStateOf("") }
    val order = listOf(EquipmentType.BREWER, EquipmentType.FILTER, EquipmentType.GRINDER, EquipmentType.KETTLE, EquipmentType.SCALE, EquipmentType.WATER)

    BrewScreen(title = "Add gear", onBack = { nav.popBackStack() }, actions = { TextButton(onClick = { nav.popBackStack() }) { Text("Done") } }) { padding ->
        CardList(padding) {
            item {
                OutlinedTextField(search, { search = it.take(60) }, Modifier.fillMaxWidth(), singleLine = true,
                    placeholder = { Text("Search") }, leadingIcon = { Icon(Icons.Filled.Search, null) })
            }
            order.forEach { type ->
                val presets = EquipmentPreset.all.filter { it.type == type && (search.isBlank() || it.name.contains(search, ignoreCase = true)) }
                if (presets.isNotEmpty()) {
                    item { SectionHeader(type.displayName) }
                    items(presets, key = { it.name }) { preset ->
                        val added = data.equipment.any { it.name == preset.name }
                        BrewCard(onClick = {
                            if (!added) {
                                container.repository.upsertEquipment(preset.makeEquipment())
                                container.haptics.tap()
                            }
                        }) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(preset.name, fontWeight = FontWeight.Medium)
                                    val detail = preset.notes.ifEmpty {
                                        preset.grinder?.let { g -> "Steps of ${g.formatDelta(g.adjustStep)}" + if (g.rangeNote.isEmpty()) "" else " · ${g.rangeNote}" } ?: ""
                                    }
                                    if (detail.isNotEmpty()) {
                                        Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                                    }
                                }
                                Icon(if (added) Icons.Filled.CheckCircle else Icons.Filled.AddCircleOutline, contentDescription = if (added) "Added" else "Add",
                                    tint = if (added) GoodGreen else MaterialTheme.colorScheme.primary)
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Create or edit gear, including grinder scales and filter properties. */
@Composable
fun EquipmentEditorScreen(nav: NavHostController, itemId: String) {
    val container = LocalContainer.current
    val existing = remember(itemId) { container.repository.data.value.equipment.firstOrNull { it.id == itemId } }
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var type by remember { mutableStateOf(existing?.type ?: EquipmentType.GRINDER) }
    var method by remember { mutableStateOf(existing?.method ?: BrewMethod.V60) }
    var flow by remember { mutableStateOf(existing?.filterFlow ?: FilterFlow.MEDIUM) }
    var idealRoast by remember { mutableStateOf(existing?.idealRoast) }
    var unit by remember { mutableStateOf(existing?.grinder?.unit ?: GrindUnit.CLICKS) }
    var step by remember { mutableStateOf<Double?>(existing?.grinder?.step ?: 1.0) }
    var adjust by remember { mutableStateOf<Double?>(existing?.grinder?.adjustStep ?: 2.0) }
    var finerIsLower by remember { mutableStateOf(existing?.grinder?.finerIsLower ?: true) }
    var rangeNote by remember { mutableStateOf(existing?.grinder?.rangeNote ?: "") }
    var notes by remember { mutableStateOf(existing?.notes ?: "") }

    fun save() {
        val cleanStep = (step ?: 1.0).clamped(0.01, 100.0)
        val item = (existing ?: Equipment(name = "", type = type)).copy(
            name = name.sanitized(InputLimits.MAX_NAME_LENGTH),
            type = type,
            notes = notes.sanitized(InputLimits.MAX_LONG_TEXT),
            method = if (type == EquipmentType.BREWER) method else existing?.method,
            filterFlow = if (type == EquipmentType.FILTER) flow else existing?.filterFlow,
            idealRoast = if (type == EquipmentType.FILTER) idealRoast else existing?.idealRoast,
            grinder = if (type == EquipmentType.GRINDER) {
                GrinderSpec(unit, cleanStep, maxOf((adjust ?: 2.0).clamped(0.01, 100.0), cleanStep), finerIsLower, rangeNote.sanitized(InputLimits.MAX_SHORT_TEXT))
            } else existing?.grinder ?: GrinderSpec(),
        )
        container.repository.upsertEquipment(item)
        nav.popBackStack()
    }

    BrewScreen(
        title = if (existing == null) "New gear" else "Edit gear",
        onBack = { nav.popBackStack() },
        actions = {
            TextButton(onClick = ::save, enabled = name.sanitized(InputLimits.MAX_NAME_LENGTH).isNotEmpty()) { Text("Save", fontWeight = FontWeight.SemiBold) }
        },
    ) { padding ->
        CardList(padding) {
            item {
                BrewCard {
                    OutlinedTextField(name, { name = it.take(80) }, label = { Text("Name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    if (existing == null) {
                        Spacer(Modifier.height(10.dp))
                        Text("Type", style = MaterialTheme.typography.labelLarge)
                        Spacer(Modifier.height(6.dp))
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            EquipmentType.entries.forEach { t -> PillChip(t.displayName, type == t, t.icon()) { type = t } }
                        }
                    }
                }
            }
            when (type) {
                EquipmentType.BREWER -> item {
                    SectionHeader("Brewer")
                    Spacer(Modifier.height(8.dp))
                    BrewCard {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            BrewMethod.entries.forEach { m -> PillChip(m.displayName, method == m) { method = m } }
                        }
                    }
                }
                EquipmentType.FILTER -> item {
                    SectionHeader("Filter paper")
                    Spacer(Modifier.height(8.dp))
                    BrewCard {
                        Text("Flow speed", style = MaterialTheme.typography.labelLarge)
                        Spacer(Modifier.height(6.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilterFlow.entries.forEach { f -> PillChip(f.displayName, flow == f) { flow = f } }
                        }
                        Spacer(Modifier.height(10.dp))
                        Text("Designed for", style = MaterialTheme.typography.labelLarge)
                        Spacer(Modifier.height(6.dp))
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            PillChip("Any roast", idealRoast == null) { idealRoast = null }
                            RoastLevel.entries.forEach { r -> PillChip(r.displayName, idealRoast == r) { idealRoast = r } }
                        }
                        Text("Faster papers shorten drawdown (less extraction). Slower papers lengthen it. Used in the brew analysis.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp))
                    }
                }
                EquipmentType.GRINDER -> item {
                    SectionHeader("Grind scale")
                    Spacer(Modifier.height(8.dp))
                    BrewCard {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            GrindUnit.entries.forEach { u -> PillChip(u.displayName, unit == u) { unit = u } }
                        }
                        Spacer(Modifier.height(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            NumberField("Smallest step", step, { step = it }, Modifier.weight(1f), 0.01..100.0, decimals = 2)
                            NumberField("Typical adjustment", adjust, { adjust = it }, Modifier.weight(1f), 0.01..100.0, decimals = 2)
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Lower number = finer", Modifier.weight(1f))
                            Switch(checked = finerIsLower, onCheckedChange = { finerIsLower = it })
                        }
                        OutlinedTextField(rangeNote, { rangeNote = it.take(200) }, label = { Text("Pour-over range (e.g. 20–30 clicks)") },
                            singleLine = true, modifier = Modifier.fillMaxWidth())
                        Text("Example: with a typical adjustment of 2, BrewLog suggests going from 24 to 22 clicks when your brew tastes sour and ran fast.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp))
                    }
                }
                else -> Unit
            }
            item {
                SectionHeader("Notes")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    OutlinedTextField(notes, { notes = it.take(2000) }, label = { Text("Notes") }, minLines = 2, modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }
}

@Composable
fun SettingsScreen(nav: NavHostController) {
    val container = LocalContainer.current
    val settings by container.settings.settings.collectAsStateWithLifecycle()
    val isDemo by container.scale.isDemo.collectAsStateWithLifecycle()
    val state by container.scale.state.collectAsStateWithLifecycle()
    var showScale by remember { mutableStateOf(false) }
    var showPressure by remember { mutableStateOf(false) }
    fun update(transform: (com.brewlog.app.domain.AppSettings) -> com.brewlog.app.domain.AppSettings) = container.settings.update(transform)

    BrewScreen(title = "Settings", onBack = { nav.popBackStack() }) { padding ->
        CardList(padding) {
            item {
                SectionHeader("Scale")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    Row(Modifier.fillMaxWidth().clickable { showScale = true }.padding(vertical = 6.dp)) {
                        Text("BOOKOO scale", Modifier.weight(1f))
                        Text(if (isDemo) "Demo" else state.label, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    SwitchRow("Demo scale (simulated pours)", isDemo) { container.scale.setDemo(it) }
                }
            }
            item { EspressoMachineSettingsCard() }
            item {
                SectionHeader("Espresso pressure monitor")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    SwitchRow("Enable pressure monitoring", settings.espressoPressureEnabled) { v ->
                        update { it.copy(espressoPressureEnabled = v) }
                        container.pressure.setEnabled(v)
                    }
                    if (settings.espressoPressureEnabled) {
                        val pressureState by container.pressure.state.collectAsStateWithLifecycle()
                        val isPressureDemo by container.pressure.isDemo.collectAsStateWithLifecycle()
                        val pressureName by container.pressure.connectedName.collectAsStateWithLifecycle()
                        HorizontalDivider(Modifier.padding(vertical = 4.dp))
                        Row(Modifier.fillMaxWidth().clickable { showPressure = true }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("BOOKOO espresso monitor", Modifier.weight(1f))
                            Text(if (isPressureDemo) "Demo" else (pressureName ?: pressureState.label), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        SwitchRow("Demo pressure (simulated shot)", isPressureDemo) { container.pressure.setDemo(it) }
                    }
                    Text(
                        "Connect a BOOKOO Espresso Monitor via Bluetooth to log and graph real-time extraction pressure (up to 12 bar) alongside weight and flow.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
            item {
                SectionHeader("Brew assistant")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    Text("Auto-start at ${fmt1(settings.autoStartThreshold)} g")
                    Slider(settings.autoStartThreshold.toFloat(), { v -> update { it.copy(autoStartThreshold = (v * 2).toInt() / 2.0) } },
                        valueRange = 0.5f..5f, steps = 8)
                    Text("Ping buffer", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.height(6.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        PingLeadMode.entries.forEach { mode -> PillChip(mode.title, settings.pingLeadMode == mode) { update { it.copy(pingLeadMode = mode) } } }
                    }
                    Spacer(Modifier.height(8.dp))
                    if (settings.pingLeadMode == PingLeadMode.FIXED) {
                        StepperRow("Ping before target", "${settings.pingLeadGrams.toInt()} g",
                            onMinus = { update { it.copy(pingLeadGrams = maxOf(0.0, it.pingLeadGrams - 1)) } },
                            onPlus = { update { it.copy(pingLeadGrams = minOf(15.0, it.pingLeadGrams + 1)) } })
                    } else {
                        Text("Reaction time ${fmt1(settings.reactionTime)} s")
                        Slider(settings.reactionTime.toFloat(), { v -> update { it.copy(reactionTime = Math.round(v * 10) / 10.0) } },
                            valueRange = 0.2f..1.5f, steps = 12)
                    }
                    SwitchRow("3-2-1 ticks before each step", settings.countdownTicks) { v -> update { it.copy(countdownTicks = v) } }
                    SwitchRow("Weigh the beans first", settings.weighBeansFirst) { v -> update { it.copy(weighBeansFirst = v) } }
                    SwitchRow("Chime at target brew time", settings.finishPing) { v -> update { it.copy(finishPing = v) } }
                    SwitchRow("Keep screen on while brewing", settings.keepAwake) { v -> update { it.copy(keepAwake = v) } }
                    Text("Automatic buffer = your pour rate × reaction time + 1 g, so you hear the ping early enough to stop right on target. " +
                        "Increase the reaction time if you often overpour. With a scale connected, a brew starts by weighing the beans (you can skip it).",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            item {
                SectionHeader("Sound & haptics")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    SwitchRow("Sounds", settings.soundEnabled) { v -> update { it.copy(soundEnabled = v) } }
                    if (settings.soundEnabled) {
                        Text("Volume")
                        Slider(settings.soundVolume.toFloat(), { v -> update { it.copy(soundVolume = v.toDouble()) } }, valueRange = 0.1f..1f)
                        SwitchRow("Play when the ringer is silent", settings.silentModeSound) { v -> update { it.copy(silentModeSound = v) } }
                    }
                    SwitchRow("Haptics", settings.hapticsEnabled) { v -> update { it.copy(hapticsEnabled = v) } }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { container.cue(BrewCue.TARGET) }) { Text("Target") }
                        OutlinedButton(onClick = { container.cue(BrewCue.NEXT_STEP) }) { Text("Next step") }
                        OutlinedButton(onClick = { container.cue(BrewCue.FINISH) }) { Text("Finish") }
                    }
                }
            }
            item {
                SectionHeader("Recipes & Feed")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    SwitchRow("Online recipe updates", settings.onlineRecipes) { v ->
                        update { it.copy(onlineRecipes = v) }
                        if (v) container.recipeFeed.syncIfNeeded(force = true)
                    }
                    Text(
                        "Automatically checks for and downloads new and updated recipes from the repository feed.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            item {
                SectionHeader("About & Updates")
                Spacer(Modifier.height(8.dp))
                val updateState by com.brewlog.app.data.AppUpdater.updateState.collectAsStateWithLifecycle()
                val context = androidx.compose.ui.platform.LocalContext.current
                val scope = androidx.compose.runtime.rememberCoroutineScope()

                BrewCard {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("Version", fontWeight = FontWeight.SemiBold)
                            Text("v${BuildConfig.VERSION_NAME}", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                        }
                        OutlinedButton(
                            onClick = {
                                scope.launch {
                                    com.brewlog.app.data.AppUpdater.checkForUpdates(BuildConfig.VERSION_NAME)
                                }
                            },
                            enabled = updateState !is com.brewlog.app.data.AppUpdater.UpdateState.Checking &&
                                updateState !is com.brewlog.app.data.AppUpdater.UpdateState.Downloading,
                        ) {
                            Text("Check for updates")
                        }
                    }

                    when (val state = updateState) {
                        is com.brewlog.app.data.AppUpdater.UpdateState.Checking -> {
                            Spacer(Modifier.height(8.dp))
                            Text("Checking GitHub for updates…", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                        }
                        is com.brewlog.app.data.AppUpdater.UpdateState.UpToDate -> {
                            Spacer(Modifier.height(8.dp))
                            Text("BrewLog is up to date.", style = MaterialTheme.typography.bodySmall, color = GoodGreen)
                        }
                        is com.brewlog.app.data.AppUpdater.UpdateState.Available -> {
                            Spacer(Modifier.height(10.dp))
                            HorizontalDivider()
                            Spacer(Modifier.height(10.dp))
                            Text("New version available: ${state.info.tagName}", fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                            if (state.info.notes.isNotBlank()) {
                                Text(state.info.notes.take(300), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Spacer(Modifier.height(8.dp))
                            PrimaryButton(text = "Download and update APK", onClick = {
                                scope.launch {
                                    com.brewlog.app.data.AppUpdater.downloadAndInstall(context, state.info)
                                }
                            })
                        }
                        is com.brewlog.app.data.AppUpdater.UpdateState.Downloading -> {
                            Spacer(Modifier.height(8.dp))
                            Text("Downloading update: ${(state.progress * 100).toInt()}%…", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                            androidx.compose.material3.LinearProgressIndicator(
                                progress = { state.progress },
                                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                            )
                        }
                        is com.brewlog.app.data.AppUpdater.UpdateState.ReadyToInstall -> {
                            Spacer(Modifier.height(8.dp))
                            Text("Download complete. Opening installer…", style = MaterialTheme.typography.bodySmall, color = GoodGreen)
                        }
                        is com.brewlog.app.data.AppUpdater.UpdateState.Error -> {
                            Spacer(Modifier.height(8.dp))
                            Text("Update check: ${state.message}", style = MaterialTheme.typography.bodySmall, color = WarnOrange)
                        }
                        is com.brewlog.app.data.AppUpdater.UpdateState.Idle -> {}
                    }

                    Spacer(Modifier.height(10.dp))
                    Text(
                        "BrewLog has no accounts or ads. Network access is used exclusively for online recipes and app update checks. All brew data stays on this device.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
    if (showScale) ScaleSheet { showScale = false }
    if (showPressure) PressureMonitorSheet { showPressure = false }
}

@Composable
private fun SwitchRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}
