@file:OptIn(ExperimentalLayoutApi::class)

package com.brewlog.app.ui.screens

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Scale
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.brewlog.app.LocalContainer
import com.brewlog.app.domain.Bean
import com.brewlog.app.domain.Equipment
import com.brewlog.app.domain.EquipmentPreset
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.domain.FilterFlow
import com.brewlog.app.domain.GrindUnit
import com.brewlog.app.domain.InputLimits
import com.brewlog.app.domain.RoastLevel
import com.brewlog.app.domain.sanitized
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.FilterIcon
import com.brewlog.app.ui.components.PillChip
import com.brewlog.app.ui.components.SectionHeader
import com.brewlog.app.ui.theme.GoodGreen

private enum class Step { WELCOME, BREWER, FILTER, GRINDER, BEANS, SCALE, DONE }

private val questionSteps = listOf(Step.BREWER, Step.FILTER, Step.GRINDER, Step.BEANS, Step.SCALE)
private const val CUSTOM_GRINDER = "__custom__"

/** First-launch setup assistant: brewer → filter → grinder → beans → scale. Every step is optional. */
@Composable
fun OnboardingScreen(onFinish: () -> Unit, onJustWeigh: () -> Unit) {
    val container = LocalContainer.current
    var step by rememberSaveable { mutableStateOf(Step.WELCOME) }
    var forward by remember { mutableStateOf(true) }
    val brewers = remember { mutableStateListOf<String>() }
    val filters = remember { mutableStateListOf<String>() }
    var grinder by rememberSaveable { mutableStateOf<String?>(null) }
    var customName by rememberSaveable { mutableStateOf("") }
    var customUnit by rememberSaveable { mutableStateOf(GrindUnit.CLICKS) }
    var grindValue by rememberSaveable { mutableStateOf<Double?>(null) }
    var beanName by rememberSaveable { mutableStateOf("") }
    var roaster by rememberSaveable { mutableStateOf("") }
    var roastLevel by rememberSaveable { mutableStateOf(RoastLevel.LIGHT) }

    val grinderSpec = if (grinder == CUSTOM_GRINDER) EquipmentPreset.specFor(customUnit)
    else EquipmentPreset.grinders.firstOrNull { it.name == grinder }?.grinder

    fun go(next: Step) {
        forward = next.ordinal > step.ordinal
        step = next
        container.haptics.tap()
    }

    val hasChoice = when (step) {
        Step.BREWER -> brewers.isNotEmpty()
        Step.FILTER -> filters.isNotEmpty()
        Step.GRINDER -> if (grinder == CUSTOM_GRINDER) customName.isNotBlank() else grinder != null
        Step.BEANS -> beanName.isNotBlank()
        else -> true
    }

    fun finish() {
        val repo = container.repository
        val setup = container.setup
        val byName = repo.data.value.equipment.associateBy { it.name }.toMutableMap()
        fun ensure(preset: EquipmentPreset): Equipment = byName[preset.name] ?: preset.makeEquipment().also {
            repo.upsertEquipment(it)
            byName[it.name] = it
        }
        brewers.mapNotNull { n -> EquipmentPreset.brewers.firstOrNull { it.name == n } }.map(::ensure).firstOrNull()?.let { setup.brewerId = it.id }
        filters.mapNotNull { n -> EquipmentPreset.filters.firstOrNull { it.name == n } }.map(::ensure).firstOrNull()?.let { setup.filterId = it.id }
        val grinderItem = if (grinder == CUSTOM_GRINDER) {
            val name = customName.sanitized(InputLimits.MAX_NAME_LENGTH)
            if (name.isEmpty()) null else byName[name] ?: Equipment(name = name, type = EquipmentType.GRINDER, grinder = EquipmentPreset.specFor(customUnit))
                .also { repo.upsertEquipment(it) }
        } else {
            EquipmentPreset.grinders.firstOrNull { it.name == grinder }?.let(::ensure)
        }
        if (grinderItem != null) setup.grinderId = grinderItem.id
        val name = beanName.sanitized(InputLimits.MAX_NAME_LENGTH)
        if (name.isNotEmpty()) {
            val bean = Bean(name = name, roaster = roaster.sanitized(InputLimits.MAX_NAME_LENGTH), roastLevel = roastLevel)
            repo.upsertBean(bean)
            setup.beanId = bean.id
        }
        // Pin after bean + grinder are set, so the typed setting isn't replaced by a history recommendation.
        if (grinderItem != null && grindValue != null) setup.pinGrind(grindValue)
        container.settings.update { it.copy(onboardingDone = true) }
        onFinish()
    }

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).systemBarsPadding().imePadding()) {
        if (step != Step.WELCOME) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { go(Step.entries[step.ordinal - 1]) }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.Center) {
                    questionSteps.forEach { q ->
                        Box(
                            Modifier.padding(horizontal = 3.dp).height(8.dp).width(if (q == step) 22.dp else 8.dp).clip(CircleShape)
                                .background(if (q.ordinal <= step.ordinal) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant),
                        )
                    }
                }
                TextButton(onClick = ::finish, enabled = step != Step.DONE) { Text(if (step == Step.DONE) "" else "Skip") }
            }
        }
        AnimatedContent(
            targetState = step,
            transitionSpec = {
                if (forward) slideInHorizontally { it } togetherWith slideOutHorizontally { -it }
                else slideInHorizontally { -it } togetherWith slideOutHorizontally { it }
            },
            modifier = Modifier.weight(1f),
            label = "onboarding",
        ) { current ->
            when (current) {
                Step.WELCOME -> Welcome(onStart = { go(Step.BREWER) }, onJustWeigh = {
                    container.settings.update { it.copy(onboardingDone = true) }
                    onJustWeigh()
                })
                Step.BREWER -> TileStep("What do you brew with?", "Pick one or more. The first one becomes your default.",
                    EquipmentPreset.brewers, brewers) { p -> Triple(p.method?.displayName ?: "", Icons.Filled.Coffee, null) }
                Step.FILTER -> FilterStep(brewers, filters)
                Step.GRINDER -> GrinderStep(grinder, { grinder = it; grindValue = null }, customName, { customName = it }, customUnit, { customUnit = it })
                Step.BEANS -> BeansStep(beanName, { beanName = it }, roaster, { roaster = it }, roastLevel) { roastLevel = it }
                Step.SCALE -> ScaleStep()
                Step.DONE -> DoneStep(brewers.firstOrNull(), filters.firstOrNull(),
                    (if (grinder == CUSTOM_GRINDER) customName.ifBlank { null } else grinder)?.let { name ->
                        name + (grindValue?.let { v -> grinderSpec?.let { " · ${it.format(v)}" } } ?: "")
                    },
                    beanName.ifBlank { null })
            }
        }
        if (step == Step.GRINDER && grinderSpec != null) {
            BrewCard(Modifier.padding(horizontal = 16.dp)) {
                Text("Your usual pour-over setting (optional)", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                GrindInput(grinderSpec, grindValue, { grindValue = it }, "", {}, null)
            }
        }
        if (step != Step.WELCOME) {
            Button(
                onClick = { if (step == Step.DONE) finish() else go(Step.entries[step.ordinal + 1]) },
                modifier = Modifier.fillMaxWidth().padding(16.dp).height(56.dp),
                shape = RoundedCornerShape(18.dp),
                colors = if (hasChoice) ButtonDefaults.buttonColors() else ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant, contentColor = MaterialTheme.colorScheme.onSurface),
            ) {
                Text(
                    when {
                        step == Step.DONE -> "Start brewing"
                        step == Step.SCALE -> "Continue"
                        step == Step.BEANS -> if (hasChoice) "Continue" else "Add beans later"
                        hasChoice -> "Continue"
                        else -> "Skip this step"
                    },
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
private fun Welcome(onStart: () -> Unit, onJustWeigh: () -> Unit) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Spacer(Modifier.height(24.dp))
        Box(Modifier.size(112.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Coffee, null, Modifier.size(52.dp), tint = Color.White)
        }
        Text("Welcome to BrewLog", fontSize = 30.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Text("Brew better pour-overs with live guidance from your scale and simple tips after every cup.",
            color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Feature(Icons.Filled.WaterDrop, "Guided pours", "Soft pings tell you when to stop and when the next pour starts.")
            Feature(Icons.AutoMirrored.Filled.ShowChart, "Every brew logged", "Pour curve, grind, beans and how it tasted.")
            Feature(Icons.Filled.AutoAwesome, "Tips for your gear", "“Grind 2 clicks finer” instead of guesswork.")
        }
        Spacer(Modifier.height(8.dp))
        Button(onClick = onStart, modifier = Modifier.fillMaxWidth().heightIn(min = 60.dp), shape = RoundedCornerShape(18.dp)) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Set up my gear", fontWeight = FontWeight.SemiBold)
                Text("About 1 minute", style = MaterialTheme.typography.labelSmall)
            }
        }
        TextButton(onClick = onJustWeigh) {
            Icon(Icons.Filled.Scale, null)
            Spacer(Modifier.width(6.dp))
            Text("Skip, just use the scale", fontWeight = FontWeight.SemiBold)
        }
        Text("You can run the setup any time from the Gear tab.", style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Feature(icon: ImageVector, title: String, text: String) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(icon, null, Modifier.size(26.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.width(14.dp))
        Column {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun StepHeader(title: String, subtitle: String) {
    Column(Modifier.padding(bottom = 12.dp)) {
        Text(title, fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(4.dp))
        Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun TileStep(
    title: String,
    subtitle: String,
    presets: List<EquipmentPreset>,
    selection: MutableList<String>,
    sectionTitle: (Int) -> String? = { null },
    describe: (EquipmentPreset) -> Triple<String, ImageVector, String?>,
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        item(span = { GridItemSpan(2) }) { StepHeader(title, subtitle) }
        presets.forEachIndexed { index, preset ->
            sectionTitle(index)?.let { section -> item(span = { GridItemSpan(2) }) { SectionHeader(section) } }
            item(key = preset.name) {
                val (detail, icon, _) = describe(preset)
                val position = selection.indexOf(preset.name)
                Tile(preset.name, detail, icon, position >= 0, if (position == 0 && selection.size > 1) "Default" else null) {
                    if (position >= 0) selection.removeAt(position) else selection.add(preset.name)
                }
            }
        }
    }
}

@Composable
private fun Tile(title: String, subtitle: String, icon: ImageVector, selected: Boolean, badge: String?, onClick: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Column(
        Modifier.fillMaxWidth().heightIn(min = 128.dp).clip(shape).background(MaterialTheme.colorScheme.surface)
            .border(2.dp, if (selected) MaterialTheme.colorScheme.primary else Color.Transparent, shape)
            .clickable(onClick = onClick).padding(14.dp),
    ) {
        Row {
            Icon(icon, null, tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
            Icon(if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, contentDescription = if (selected) "Selected" else null,
                tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f))
        }
        Spacer(Modifier.weight(1f, fill = false).height(18.dp))
        Text(title, fontWeight = FontWeight.SemiBold, maxLines = 2)
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (subtitle.isNotEmpty()) {
                Text(subtitle, Modifier.weight(1f, fill = false), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
            }
            if (badge != null) {
                Spacer(Modifier.width(6.dp))
                Text(badge, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.18f))
                        .padding(horizontal = 6.dp, vertical = 2.dp))
            }
        }
    }
}

@Composable
private fun FilterStep(brewers: List<String>, filters: MutableList<String>) {
    val shapes = brewers.mapNotNull { n -> EquipmentPreset.brewers.firstOrNull { it.name == n }?.shape }.toSet()
    val matching = if (shapes.isEmpty()) EquipmentPreset.filters else EquipmentPreset.filters.filter { it.shape == null || it.shape in shapes }
    val others = if (shapes.isEmpty()) emptyList() else EquipmentPreset.filters.filter { it !in matching }
    val ordered = matching + others
    TileStep(
        "Which filter papers do you use?",
        "Paper flow speed changes drawdown time, so BrewLog uses it in your tips.",
        ordered, filters,
        sectionTitle = { index ->
            when {
                shapes.isEmpty() -> null
                index == 0 -> "Fits your brewer"
                index == matching.size && others.isNotEmpty() -> "Other papers"
                else -> null
            }
        },
    ) { preset ->
        val detail = listOfNotNull(preset.flow?.let { "${it.displayName} flow" }, preset.idealRoast?.let { "${it.displayName.lowercase()} roasts" })
            .joinToString(" · ")
        Triple(detail, if (preset.flow == FilterFlow.FAST) Icons.Filled.Speed else FilterIcon, null)
    }
}

@Composable
private fun GrinderStep(
    selected: String?, onSelect: (String?) -> Unit,
    customName: String, onCustomName: (String) -> Unit,
    customUnit: GrindUnit, onCustomUnit: (GrindUnit) -> Unit,
) {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp)) {
        item { StepHeader("Which grinder do you use?", "BrewLog learns your grinder's scale, so tips can say exactly how many clicks to change.") }
        items(EquipmentPreset.grinders, key = { it.name }) { preset ->
            val spec = preset.grinder
            val detail = spec?.let { if (it.rangeNote.isEmpty()) it.unit.displayName else "${it.unit.displayName} · pour-over ${it.rangeNote}" } ?: ""
            GrinderRow(preset.name, detail, selected == preset.name) { onSelect(if (selected == preset.name) null else preset.name) }
        }
        item {
            GrinderRow("Other grinder", "Type its name and how its setting works", selected == CUSTOM_GRINDER) {
                onSelect(if (selected == CUSTOM_GRINDER) null else CUSTOM_GRINDER)
            }
        }
        if (selected == CUSTOM_GRINDER) {
            item {
                BrewCard(Modifier.padding(top = 8.dp)) {
                    OutlinedTextField(customName, { onCustomName(it.take(80)) }, label = { Text("Grinder name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(GrindUnit.CLICKS, GrindUnit.NUMBERS, GrindUnit.DIAL).forEach { u -> PillChip(u.displayName, customUnit == u) { onCustomUnit(u) } }
                    }
                    Text("You can fine-tune step sizes later in Gear.", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
                }
            }
        }
    }
}

@Composable
private fun GrinderRow(name: String, detail: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surface)
            .clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, contentDescription = null,
            tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
        Spacer(Modifier.width(14.dp))
        Column {
            Text(name, fontWeight = FontWeight.Medium)
            if (detail.isNotEmpty()) Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    Spacer(Modifier.height(6.dp))
}

@Composable
private fun BeansStep(
    name: String, onName: (String) -> Unit, roaster: String, onRoaster: (String) -> Unit,
    roastLevel: RoastLevel, onRoastLevel: (RoastLevel) -> Unit,
) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        StepHeader("Got a bag of beans open?", "Optional. Roast level and age help BrewLog explain sour or flat cups. You can also add beans after a brew.")
        BrewCard {
            OutlinedTextField(name, { onName(it.take(80)) }, label = { Text("Coffee name, e.g. Ethiopia Guji") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(roaster, { onRoaster(it.take(80)) }, label = { Text("Roaster (optional)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(10.dp))
            Text("Roast level", fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(6.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                RoastLevel.entries.forEach { level -> PillChip(level.displayName, roastLevel == level) { onRoastLevel(level) } }
            }
        }
    }
}

@Composable
private fun ScaleStep() {
    val scale = LocalContainer.current.scale
    val isDemo by scale.isDemo.collectAsStateWithLifecycle()
    var showSheet by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        StepHeader("Connect your scale",
            "BrewLog works with the BOOKOO Themis Mini and the Timemore Black Mirror Dot. Switch it on and tap below. No scale? The timer works on its own.")
        ScaleStatusCard { showSheet = true }
        BrewCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Demo scale", fontWeight = FontWeight.Medium)
                    Text("Simulated pours to try BrewLog without a scale", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Switch(checked = isDemo, onCheckedChange = { scale.setDemo(it) })
            }
        }
        Text("You can connect any time from the Brew tab.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if (showSheet) ScaleSheet { showSheet = false }
}

@Composable
private fun DoneStep(brewer: String?, filter: String?, grinder: String?, bean: String?) {
    val scale = LocalContainer.current.scale
    val ready by scale.ready.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Spacer(Modifier.height(16.dp))
        Box(Modifier.size(96.dp).clip(CircleShape).background(GoodGreen), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Check, null, Modifier.size(48.dp), tint = Color.White)
        }
        Text("You're all set", fontSize = 30.sp, fontWeight = FontWeight.Bold)
        Text("Change anything later in the Gear and Beans tabs.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        BrewCard {
            SummaryRow("Brewer", Icons.Filled.Coffee, brewer)
            SummaryRow("Filter", FilterIcon, filter)
            SummaryRow("Grinder", Icons.Filled.Tune, grinder)
            SummaryRow("Beans", Icons.Filled.Eco, bean)
            SummaryRow("Scale", Icons.Filled.Scale, if (ready) scale.displayName else "Timer only for now")
        }
    }
}

@Composable
private fun SummaryRow(title: String, icon: ImageVector, value: String?) {
    Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(8.dp))
        Text(title, Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value ?: "Skipped", color = if (value == null) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface, maxLines = 1)
    }
}
