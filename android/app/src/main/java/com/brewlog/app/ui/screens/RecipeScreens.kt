package com.brewlog.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.brewlog.app.LocalContainer
import com.brewlog.app.domain.BrewMethod
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.RecipeFilter
import com.brewlog.app.domain.RecipeLibrary
import com.brewlog.app.domain.RecipeStep
import com.brewlog.app.domain.StepKind
import com.brewlog.app.domain.ValveState
import com.brewlog.app.domain.grams
import com.brewlog.app.domain.mmss
import com.brewlog.app.domain.newId
import com.brewlog.app.domain.validated
import com.brewlog.app.ui.Routes
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.MethodBadge
import com.brewlog.app.ui.components.PillChip
import com.brewlog.app.ui.components.SectionHeader
import com.brewlog.app.ui.components.StatView
import com.brewlog.app.ui.components.TasteProfileBars
import com.brewlog.app.ui.components.icon
import com.brewlog.app.ui.switchTab

@Composable
fun RecipeListScreen(nav: NavHostController) {
    val container = LocalContainer.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val data by container.repository.data.collectAsStateWithLifecycle()
    val settings by container.settings.settings.collectAsStateWithLifecycle()
    var showMenu by remember { mutableStateOf(false) }
    var showImportDialog by remember { mutableStateOf(false) }
    var importResult by remember { mutableStateOf<String?>(null) }

    val filePicker = androidx.activity.compose.rememberLauncherForActivityResult(
        contract = androidx.activity.result.contract.ActivityResultContracts.GetContent(),
    ) { uri ->
        if (uri != null) {
            try {
                val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes != null) {
                    val summary = com.brewlog.app.data.DataImporter.importData(bytes, container.repository, container.presets)
                    importResult = summary.message
                }
            } catch (e: Exception) {
                importResult = "Import failed: ${e.localizedMessage ?: "Unknown error"}"
            }
        }
    }

    BrewScreen(
        title = "Recipes",
        actions = {
            androidx.compose.foundation.layout.Box {
                IconButton(onClick = { showMenu = true }) {
                    Icon(Icons.Filled.Add, contentDescription = "Add or import recipe")
                }
                DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                    DropdownMenuItem(
                        text = { Text("New recipe") },
                        onClick = {
                            showMenu = false
                            nav.navigate(Routes.recipeEditor(Routes.NEW))
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("Import from file…") },
                        onClick = {
                            showMenu = false
                            showImportDialog = true
                        },
                    )
                    if (data.customRecipes.isNotEmpty()) {
                        DropdownMenuItem(
                            text = { Text("Share my recipes") },
                            onClick = {
                                showMenu = false
                                val jsonStr = com.brewlog.app.domain.RecipeFile.encode(data.customRecipes)
                                val sendIntent = android.content.Intent().apply {
                                    action = android.content.Intent.ACTION_SEND
                                    putExtra(android.content.Intent.EXTRA_TEXT, jsonStr)
                                    type = "application/json"
                                }
                                val shareIntent = android.content.Intent.createChooser(sendIntent, "Share recipes")
                                context.startActivity(shareIntent)
                            },
                        )
                    }
                }
            }
        },
    ) { padding ->
        CardList(padding) {
            val filter = BrewMethod.entries.firstOrNull { it.name == settings.recipeFilter }
            item(key = "filter") {
                MethodFilterBar(data.customRecipes + container.presets, filter, brewerMethod = brewerMethod(container)) { method ->
                    container.settings.update { it.copy(recipeFilter = method?.name ?: "") }
                }
            }
            recipeSections(data.customRecipes, container.presets, filter) { recipe -> RecipeRow(recipe) { nav.navigate(Routes.recipe(recipe.id)) } }
        }
    }

    if (showImportDialog) {
        com.brewlog.app.ui.dialogs.ImportFormatDialog(
            onDismissRequest = { showImportDialog = false },
            onSelectFileToImport = {
                showImportDialog = false
                filePicker.launch("*/*")
            },
        )
    }

    importResult?.let { message ->
        AlertDialog(
            onDismissRequest = { importResult = null },
            title = { Text("Import") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { importResult = null }) { Text("OK") } },
        )
    }
}

@Composable
fun RecipePickerScreen(nav: NavHostController) {
    val container = LocalContainer.current
    val data by container.repository.data.collectAsStateWithLifecycle()
    val yours = brewerMethod(container)
    // Start with the recipes for the brewer you've selected.
    var filter by rememberSaveable { mutableStateOf(yours?.takeIf { it != BrewMethod.UNIVERSAL }) }
    BrewScreen(title = "Choose recipe", onBack = { nav.popBackStack() }) { padding ->
        CardList(padding) {
            item(key = "filter") { MethodFilterBar(data.customRecipes + container.presets, filter, brewerMethod = yours) { filter = it } }
            recipeSections(data.customRecipes, container.presets, filter) { recipe ->
                RecipeRow(recipe, selected = container.setup.recipe.id == recipe.id) {
                    container.setup.select(recipe)
                    container.haptics.tap()
                    nav.popBackStack()
                }
            }
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.recipeSections(
    custom: List<Recipe>, presets: List<Recipe>, method: BrewMethod?, row: @Composable (Recipe) -> Unit,
) {
    RecipeFilter.sections(custom, presets, method).forEach { section ->
        val prefix = if (section.title == "My recipes") "c-" else ""
        item(key = "h-" + section.title) { SectionHeader(section.title) }
        items(section.recipes, key = { prefix + it.id }) { row(it) }
    }
}

/** The type of the brewer selected on the Brew tab. */
private fun brewerMethod(container: com.brewlog.app.AppContainer): BrewMethod? =
    container.repository.data.value.equipment
        .firstOrNull { it.id == container.setup.brewerId && it.type == EquipmentType.BREWER }?.method

/** "All" plus one chip per brewer type. Tapping the selected chip again shows all recipes. */
@Composable
private fun MethodFilterBar(recipes: List<Recipe>, selection: BrewMethod?, brewerMethod: BrewMethod?, onSelect: (BrewMethod?) -> Unit) {
    val haptics = LocalContainer.current.haptics
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        item { FilterChip(selected = selection == null, onClick = { onSelect(null) }, label = { Text("All") }) }
        items(RecipeFilter.methods(recipes)) { method ->
            FilterChip(
                selected = selection == method,
                onClick = { onSelect(if (selection == method) null else method); haptics.tap() },
                label = { Text(if (method == brewerMethod) "${method.displayName} · yours" else method.displayName) },
            )
        }
    }
}

@Composable
private fun RecipeRow(recipe: Recipe, selected: Boolean = false, onClick: () -> Unit) {
    BrewCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(recipe.name, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(recipe.ratioText, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (selected) {
                Spacer(Modifier.width(8.dp))
                Icon(Icons.Filled.CheckCircle, null, tint = MaterialTheme.colorScheme.primary)
            }
        }
        Text(recipe.author, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(4.dp))
        Text(recipe.tasteNotes, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
        Spacer(Modifier.height(4.dp))
        Text("${recipe.dose.grams()} · ${recipe.water.grams()} · ${recipe.temperature.toInt()}° · ${recipe.targetTime.mmss()}",
            style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun RecipeDetailScreen(nav: NavHostController, recipeId: String) {
    val container = LocalContainer.current
    val data by container.repository.data.collectAsStateWithLifecycle()
    val recipe = data.customRecipes.firstOrNull { it.id == recipeId } ?: container.presets.firstOrNull { it.id == recipeId }
    var menu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    if (recipe == null) {
        androidx.compose.runtime.LaunchedEffect(Unit) { nav.popBackStack() }
        return
    }
    val isCustom = recipe.isCustom == true

    BrewScreen(
        title = recipe.name,
        onBack = { nav.popBackStack() },
        actions = {
            IconButton(onClick = { menu = true }) { Icon(Icons.Filled.Edit, contentDescription = "Edit") }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                if (isCustom) {
                    DropdownMenuItem(text = { Text("Edit") }, leadingIcon = { Icon(Icons.Filled.Edit, null) },
                        onClick = { menu = false; nav.navigate(Routes.recipeEditor(recipe.id)) })
                }
                DropdownMenuItem(text = { Text("Duplicate & edit") }, leadingIcon = { Icon(Icons.Filled.ContentCopy, null) },
                    onClick = { menu = false; nav.navigate(Routes.recipeEditor(recipe.id, duplicate = true)) })
                if (isCustom) {
                    DropdownMenuItem(text = { Text("Delete") }, leadingIcon = { Icon(Icons.Filled.Delete, null) },
                        onClick = { menu = false; confirmDelete = true })
                }
            }
        },
        bottomBar = {
            Column(Modifier.padding(16.dp)) {
                PrimaryButton("Brew this", Icons.Filled.WaterDrop) {
                    container.setup.select(recipe)
                    nav.switchTab(Routes.BREW)
                }
            }
        },
    ) { padding ->
        CardList(padding) {
            item {
                BrewCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        MethodBadge(recipe.method)
                        Spacer(Modifier.weight(1f))
                        Text(recipe.author, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (recipe.summary.isNotEmpty()) {
                        Spacer(Modifier.height(10.dp))
                        Text(recipe.summary, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
            item {
                SectionHeader("How it should taste")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    if (recipe.tasteNotes.isNotEmpty()) {
                        Text(recipe.tasteNotes, style = MaterialTheme.typography.bodyMedium)
                        Spacer(Modifier.height(12.dp))
                    }
                    TasteProfileBars(recipe.taste)
                }
            }
            item {
                SectionHeader("Parameters")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    Row {
                        StatView(recipe.dose.grams(), "Coffee")
                        StatView(recipe.water.grams(), "Water")
                        StatView(recipe.ratioText, "Ratio")
                    }
                    Spacer(Modifier.height(10.dp))
                    Row {
                        StatView("${recipe.temperature.toInt()} °C", "Temp")
                        StatView(recipe.targetTime.mmss(), "Total time")
                        StatView("${recipe.flowMin.toInt()}–${recipe.flowMax.toInt()}", "Pour g/s")
                    }
                    HorizontalDivider(Modifier.padding(vertical = 10.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Tune, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(recipe.grind, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
            item {
                SectionHeader("Steps")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    recipe.steps.forEach { step ->
                        Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.Top) {
                            Text(step.time.mmss(), Modifier.width(48.dp), fontWeight = FontWeight.Bold)
                            Icon(step.kind.icon, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
                            Spacer(Modifier.width(10.dp))
                            Column {
                                Text(step.headline, fontWeight = FontWeight.SemiBold)
                                step.note?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            }
                        }
                    }
                }
            }
            if (recipe.tips.isNotEmpty()) {
                item {
                    SectionHeader("Tips")
                    Spacer(Modifier.height(8.dp))
                    BrewCard {
                        recipe.tips.forEach { tip ->
                            Row(Modifier.padding(vertical = 4.dp)) {
                                Icon(Icons.Filled.Lightbulb, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                                Spacer(Modifier.width(8.dp))
                                Text(tip, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
            }
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete this recipe?") },
            confirmButton = {
                TextButton(onClick = { container.repository.deleteRecipe(recipe.id); confirmDelete = false; nav.popBackStack() }) {
                    Text("Delete", color = Color(0xFFFF3B30))
                }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
        )
    }
}

private class EditableStep(step: RecipeStep) {
    val key = newId()
    var kind by mutableStateOf(step.kind)
    var time by mutableStateOf(step.time)
    var target by mutableStateOf(step.target)
    var valve by mutableStateOf(step.valve)
    var note by mutableStateOf(step.note ?: "")
    fun toStep() = RecipeStep(kind, time, if (kind.isPour) target ?: 0.0 else null, valve, note.ifBlank { null })
}

@Composable
fun RecipeEditorScreen(nav: NavHostController, recipeId: String, duplicate: Boolean) {
    val container = LocalContainer.current
    val original = remember(recipeId) {
        val data = container.repository.data.value
        val base = data.customRecipes.firstOrNull { it.id == recipeId } ?: container.presets.firstOrNull { it.id == recipeId }
        when {
            base == null -> RecipeLibrary.blankRecipe()
            duplicate -> base.copy(id = "custom-" + newId(), name = if (base.isCustom == true) "${base.name} copy" else "My ${base.name}", isCustom = true)
            else -> base
        }
    }
    var name by remember { mutableStateOf(original.name) }
    var author by remember { mutableStateOf(original.author) }
    var method by remember { mutableStateOf(original.method) }
    var dose by remember { mutableStateOf<Double?>(original.dose) }
    var water by remember { mutableStateOf<Double?>(original.water) }
    var temperature by remember { mutableStateOf<Double?>(original.temperature) }
    var targetTime by remember { mutableStateOf(original.targetTime) }
    var flowMin by remember { mutableStateOf<Double?>(original.flowMin) }
    var flowMax by remember { mutableStateOf<Double?>(original.flowMax) }
    var grind by remember { mutableStateOf(original.grind) }
    var tasteNotes by remember { mutableStateOf(original.tasteNotes) }
    var summary by remember { mutableStateOf(original.summary) }
    var taste by remember { mutableStateOf(original.taste) }
    val steps = remember { mutableStateListOf<EditableStep>().apply { addAll(original.steps.map(::EditableStep)) } }

    fun save() {
        val recipe = original.copy(
            name = name, author = author, method = method,
            dose = dose ?: original.dose, water = water ?: original.water, temperature = temperature ?: original.temperature,
            targetTime = targetTime, flowMin = flowMin ?: original.flowMin, flowMax = flowMax ?: original.flowMax,
            grind = grind, tasteNotes = tasteNotes, summary = summary, taste = taste,
            steps = steps.map { it.toStep() }, isCustom = true,
        ).validated()
        container.repository.upsertRecipe(recipe)
        nav.popBackStack()
    }

    BrewScreen(
        title = if (recipeId == Routes.NEW || duplicate) "New recipe" else "Edit recipe",
        onBack = { nav.popBackStack() },
        actions = { TextButton(onClick = ::save) { Text("Save", fontWeight = FontWeight.SemiBold) } },
    ) { padding ->
        CardList(padding) {
            item {
                SectionHeader("Recipe")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    OutlinedTextField(name, { name = it.take(80) }, label = { Text("Name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(author, { author = it.take(80) }, label = { Text("Author") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        BrewMethod.entries.forEach { m -> PillChip(m.displayName, method == m) { method = m } }
                    }
                }
            }
            item {
                SectionHeader("Parameters")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NumberField("Coffee g", dose, { dose = it }, Modifier.weight(1f), 1.0..150.0)
                        NumberField("Water g", water, { water = it }, Modifier.weight(1f), 10.0..3000.0, decimals = 0)
                        NumberField("Temp °C", temperature, { temperature = it }, Modifier.weight(1f), 0.0..100.0, decimals = 0)
                    }
                    Spacer(Modifier.height(8.dp))
                    StepperRow("Total time", targetTime.mmss(), onMinus = { targetTime = maxOf(30.0, targetTime - 5) },
                        onPlus = { targetTime = minOf(1200.0, targetTime + 5) })
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NumberField("Min pour g/s", flowMin, { flowMin = it }, Modifier.weight(1f), 0.5..30.0)
                        NumberField("Max pour g/s", flowMax, { flowMax = it }, Modifier.weight(1f), 1.0..40.0)
                    }
                    OutlinedTextField(grind, { grind = it.take(200) }, label = { Text("Grind description") }, modifier = Modifier.fillMaxWidth())
                }
            }
            item {
                SectionHeader("Steps")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    steps.forEachIndexed { index, step ->
                        if (index > 0) HorizontalDivider(Modifier.padding(vertical = 8.dp))
                        StepEditor(step, showValve = method == BrewMethod.HYBRID) { steps.removeAt(index) }
                    }
                    Spacer(Modifier.height(8.dp))
                    OutlinedButton(
                        onClick = {
                            val last = steps.lastOrNull()
                            val lastTarget = steps.lastOrNull { it.kind.isPour }?.target ?: 0.0
                            steps.add(EditableStep(RecipeStep(StepKind.POUR, (last?.time ?: -30.0) + 30, minOf(lastTarget + 50, water ?: 250.0))))
                        },
                        enabled = steps.size < 30,
                    ) { Text("Add step") }
                    Text("Pour targets are cumulative scale weights. BrewLog pings a little before each target and chimes when each step starts.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            item {
                SectionHeader("How it should taste")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    OutlinedTextField(tasteNotes, { tasteNotes = it.take(2000) }, label = { Text("Taste description") }, minLines = 2, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(8.dp))
                    TasteStepper("Acidity", taste.acidity) { taste = taste.copy(acidity = it) }
                    TasteStepper("Sweetness", taste.sweetness) { taste = taste.copy(sweetness = it) }
                    TasteStepper("Body", taste.body) { taste = taste.copy(body = it) }
                    TasteStepper("Clarity", taste.clarity) { taste = taste.copy(clarity = it) }
                    OutlinedTextField(summary, { summary = it.take(2000) }, label = { Text("Summary") }, minLines = 2, modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }
}

@Composable
private fun TasteStepper(label: String, value: Int, onChange: (Int) -> Unit) {
    StepperRow(label, "$value", onMinus = { onChange((value - 1).coerceIn(1, 5)) }, onPlus = { onChange((value + 1).coerceIn(1, 5)) })
}

@Composable
private fun StepEditor(step: EditableStep, showValve: Boolean, onDelete: () -> Unit) {
    var kindMenu by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.clickable { kindMenu = true }.padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(step.kind.icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(6.dp))
                Text(step.kind.title, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                DropdownMenu(expanded = kindMenu, onDismissRequest = { kindMenu = false }) {
                    StepKind.entries.forEach { kind ->
                        DropdownMenuItem(text = { Text(kind.title) }, leadingIcon = { Icon(kind.icon, null) },
                            onClick = { step.kind = kind; kindMenu = false })
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onDelete) { Icon(Icons.Filled.Delete, contentDescription = "Delete step") }
        }
        StepperRow("Starts at", step.time.mmss(), onMinus = { step.time = maxOf(0.0, step.time - 5) }, onPlus = { step.time = minOf(1200.0, step.time + 5) })
        if (step.kind.isPour) {
            NumberField("Pour to (g total)", step.target, { step.target = it }, Modifier.fillMaxWidth(), 0.0..3000.0, decimals = 0)
            if (showValve) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    PillChip("Valve –", step.valve == null) { step.valve = null }
                    PillChip("Open", step.valve == ValveState.OPEN) { step.valve = ValveState.OPEN }
                    PillChip("Closed", step.valve == ValveState.CLOSED) { step.valve = ValveState.CLOSED }
                }
            }
        }
        OutlinedTextField(step.note, { step.note = it.take(200) }, label = { Text("Note (optional)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    }
}
