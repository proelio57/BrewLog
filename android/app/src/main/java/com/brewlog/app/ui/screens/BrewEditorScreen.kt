package com.brewlog.app.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.brewlog.app.LocalContainer
import com.brewlog.app.analysis.analyze
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.domain.InputLimits
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.formatDate
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.FilterIcon
import com.brewlog.app.ui.components.MenuPickerRow
import com.brewlog.app.ui.components.PickerOption
import com.brewlog.app.ui.components.SectionHeader

/**
 * Screen to edit an existing brew's date, recipe, amounts, time, temperature, and gear.
 * Matches iOS BrewEditorView.swift.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrewEditorScreen(nav: NavHostController, brewId: String) {
    val container = LocalContainer.current
    val repo = container.repository
    val data by repo.data.collectAsStateWithLifecycle()
    val brew = data.brews.firstOrNull { it.id == brewId }

    if (brew == null) {
        nav.popBackStack()
        return
    }

    val recipes = remember(data.customRecipes, container.presets) {
        data.customRecipes + container.presets
    }

    var dateMillis by remember { mutableLongStateOf(brew.date) }
    var selectedRecipeId by remember { mutableStateOf(brew.recipeId) }
    var dose by remember { mutableDoubleStateOf(brew.dose) }
    var finalWeight by remember { mutableDoubleStateOf(brew.finalWeight) }
    val totalSec = brew.totalTime.toInt()
    var minutes by remember { mutableIntStateOf(totalSec / 60) }
    var seconds by remember { mutableIntStateOf(totalSec % 60) }
    var waterTemp by remember { mutableDoubleStateOf(brew.waterTemp) }
    var brewerId by remember { mutableStateOf(brew.brewerId) }
    var grinderId by remember { mutableStateOf(brew.grinderId) }
    var filterId by remember { mutableStateOf(brew.filterId) }

    var showDatePicker by remember { mutableStateOf(false) }

    val datePickerState = rememberDatePickerState(initialSelectedDateMillis = dateMillis)

    BrewScreen(
        title = "Edit brew",
        onBack = { nav.popBackStack() },
        actions = {
            TextButton(onClick = {
                val newDose = dose.coerceIn(0.0, InputLimits.MAX_DOSE)
                val oldDose = brew.dose
                val clampedWater = finalWeight.coerceIn(0.0, InputLimits.MAX_WATER)
                val clampedTemp = waterTemp.coerceIn(0.0, 100.0)
                val clampedTime = (maxOf(minutes, 0) * 60 + maxOf(seconds, 0)).toDouble()
                    .coerceIn(0.0, InputLimits.MAX_BREW_SECONDS)

                val chosenRecipe = recipes.firstOrNull { it.id == selectedRecipeId }
                val updatedRecipe: Recipe?
                val updatedRecipeId: String
                val updatedRecipeName: String
                val updatedTargetWater: Double

                if (selectedRecipeId != brew.recipeId && chosenRecipe != null) {
                    val scaled = chosenRecipe.scaled(if (newDose > 0) newDose else chosenRecipe.dose)
                    updatedRecipe = scaled
                    updatedRecipeId = chosenRecipe.id
                    updatedRecipeName = chosenRecipe.name
                    updatedTargetWater = scaled.water
                } else if (newDose != oldDose && newDose > 0 && brew.recipe != null) {
                    val scaled = brew.recipe.scaled(newDose)
                    updatedRecipe = scaled
                    updatedRecipeId = brew.recipeId
                    updatedRecipeName = brew.recipeName
                    updatedTargetWater = scaled.water
                } else {
                    updatedRecipe = brew.recipe
                    updatedRecipeId = brew.recipeId
                    updatedRecipeName = brew.recipeName
                    updatedTargetWater = brew.targetWater
                }

                val brewerItem = data.equipment.firstOrNull { it.id == brewerId }
                val grinderItem = data.equipment.firstOrNull { it.id == grinderId }
                val filterItem = data.equipment.firstOrNull { it.id == filterId }

                repo.update { current ->
                    // Adjust bean remaining if dose changed
                    val beans = if (newDose != oldDose && brew.beanId != null) {
                        current.beans.map { bean ->
                            if (bean.id == brew.beanId) {
                                val adjusted = (bean.remaining - (newDose - oldDose)).coerceIn(0.0, InputLimits.MAX_BAG_WEIGHT)
                                bean.copy(remaining = adjusted)
                            } else bean
                        }
                    } else current.beans

                    val updatedBrews = current.brews.map { b ->
                        if (b.id == brew.id) {
                            val modified = b.copy(
                                date = minOf(dateMillis, System.currentTimeMillis()),
                                recipeId = updatedRecipeId,
                                recipeName = updatedRecipeName,
                                recipe = updatedRecipe,
                                dose = newDose,
                                targetWater = updatedTargetWater,
                                finalWeight = clampedWater,
                                waterTemp = clampedTemp,
                                totalTime = clampedTime,
                                brewerId = brewerItem?.id ?: if (brewerId == null) null else b.brewerId,
                                brewerName = brewerItem?.name ?: b.brewerName,
                                grinderId = grinderItem?.id ?: if (grinderId == null) null else b.grinderId,
                                grinderName = grinderItem?.name ?: b.grinderName,
                                grinderSpec = grinderItem?.grinder ?: b.grinderSpec,
                                filterId = filterItem?.id ?: if (filterId == null) null else b.filterId,
                                filterName = filterItem?.name ?: b.filterName,
                                filterFlow = filterItem?.filterFlow ?: b.filterFlow,
                                filterIdealRoast = filterItem?.idealRoast ?: b.filterIdealRoast,
                            )
                            val samples = repo.samples(brew.id)
                            val analysis = modified.analyze(current.brews, current.beans.firstOrNull { it.id == modified.beanId }, samples, container.presets, repo.machineSamples(brew.id))
                            if (analysis != null) modified.copy(suggestedGrind = analysis.suggestedGrind) else modified
                        } else b
                    }

                    current.copy(beans = beans, brews = updatedBrews)
                }

                nav.popBackStack()
            }) {
                Text("Save", fontWeight = FontWeight.SemiBold)
            }
        },
    ) { padding ->
        CardList(padding) {
            item {
                SectionHeader("Date & Recipe")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Date", Modifier.weight(1f))
                        TextButton(onClick = { showDatePicker = true }) {
                            Text(formatDate(dateMillis, withTime = false), fontWeight = FontWeight.Medium)
                        }
                    }
                    HorizontalDivider(Modifier.padding(vertical = 6.dp))

                    val recipeOptions = listOf(PickerOption("", if (brew.recipe == null) "None" else brew.recipeName)) +
                        recipes.map { PickerOption(it.id, it.name) }

                    MenuPickerRow(
                        title = "Recipe",
                        icon = Icons.AutoMirrored.Filled.MenuBook,
                        options = recipeOptions,
                        selectedId = selectedRecipeId,
                        onSelect = { selectedRecipeId = it ?: "" },
                    )
                }
            }

            item {
                SectionHeader("Amounts & Time")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    NumberRow("Coffee dose", dose, "g", Icons.Filled.Coffee) { dose = it }
                    HorizontalDivider(Modifier.padding(vertical = 6.dp))
                    NumberRow("Water weight", finalWeight, "g", Icons.Filled.WaterDrop) { finalWeight = it }
                    HorizontalDivider(Modifier.padding(vertical = 6.dp))
                    NumberRow("Water temp", waterTemp, "°C", Icons.Filled.Thermostat) { waterTemp = it }
                    HorizontalDivider(Modifier.padding(vertical = 6.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Total time", Modifier.weight(1f))
                        OutlinedTextField(
                            value = if (minutes == 0) "" else minutes.toString(),
                            onValueChange = { minutes = it.filter { c -> c.isDigit() }.take(2).toIntOrNull() ?: 0 },
                            label = { Text("m") },
                            modifier = Modifier.width(64.dp),
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(":")
                        Spacer(Modifier.width(6.dp))
                        OutlinedTextField(
                            value = if (seconds == 0) "" else seconds.toString(),
                            onValueChange = { seconds = it.filter { c -> c.isDigit() }.take(2).toIntOrNull() ?: 0 },
                            label = { Text("s") },
                            modifier = Modifier.width(64.dp),
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        )
                    }
                }
            }

            item {
                SectionHeader("Gear")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    val brewers = data.equipment.filter { it.type == EquipmentType.BREWER }
                    val brewerOptions = listOf(PickerOption("", "None")) + brewers.map { PickerOption(it.id, it.name) }
                    MenuPickerRow("Brewer", Icons.Filled.Coffee, brewerOptions, brewerId) { brewerId = it }

                    HorizontalDivider(Modifier.padding(vertical = 6.dp))
                    val grinders = data.equipment.filter { it.type == EquipmentType.GRINDER }
                    val grinderOptions = listOf(PickerOption("", "None")) + grinders.map { PickerOption(it.id, it.name) }
                    MenuPickerRow("Grinder", Icons.Filled.Build, grinderOptions, grinderId) { grinderId = it }

                    HorizontalDivider(Modifier.padding(vertical = 6.dp))
                    val filters = data.equipment.filter { it.type == EquipmentType.FILTER }
                    val filterOptions = listOf(PickerOption("", "None")) + filters.map { PickerOption(it.id, it.name) }
                    MenuPickerRow("Filter", FilterIcon, filterOptions, filterId) { filterId = it }
                }
            }
        }
    }

    if (showDatePicker) {
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    datePickerState.selectedDateMillis?.let { dateMillis = it }
                    showDatePicker = false
                }) {
                    Text("OK")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) {
                    Text("Cancel")
                }
            },
        ) {
            DatePicker(state = datePickerState)
        }
    }
}

@Composable
private fun NumberRow(
    title: String,
    value: Double,
    unit: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onChange: (Double) -> Unit,
) {
    var text by remember(value) { mutableStateOf(if (value > 0) String.format(java.util.Locale.US, "%.1f", value) else "") }
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        androidx.compose.material3.Icon(icon, null, Modifier.padding(end = 8.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, Modifier.weight(1f))
        OutlinedTextField(
            value = text,
            onValueChange = { newText ->
                text = newText
                val parsed = newText.replace(',', '.').toDoubleOrNull()
                if (parsed != null && parsed >= 0) onChange(parsed)
            },
            modifier = Modifier.width(90.dp),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            trailingIcon = { Text(unit, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) },
        )
    }
}
