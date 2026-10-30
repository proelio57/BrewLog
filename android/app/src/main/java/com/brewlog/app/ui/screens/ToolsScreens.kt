@file:OptIn(ExperimentalLayoutApi::class)

package com.brewlog.app.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.brewlog.app.LocalContainer
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.Equipment
import com.brewlog.app.domain.EquipmentPreset
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.domain.Extraction
import com.brewlog.app.domain.GrindConverter
import com.brewlog.app.domain.GrinderSpec
import com.brewlog.app.domain.WaterChemistry
import com.brewlog.app.domain.fmt1
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.PillChip
import com.brewlog.app.ui.components.SectionHeader
import com.brewlog.app.ui.theme.GoodGreen
import com.brewlog.app.ui.theme.WarnOrange
import java.util.Locale

// Gear → Tools: extraction calculator, water recipes and grind converter. Port of ToolViews.swift.

private fun fmt2(value: Double) = String.format(Locale.US, "%.2f", value)

// MARK: - Extraction

@Composable
fun ExtractionCalculatorScreen(nav: NavHostController) {
    var espresso by rememberSaveable { mutableStateOf(false) }
    var dose by rememberSaveable { mutableStateOf<Double?>(15.0) }
    var beverage by rememberSaveable { mutableStateOf<Double?>(null) }
    var water by rememberSaveable { mutableStateOf<Double?>(250.0) }
    var tds by rememberSaveable { mutableStateOf<Double?>(null) }

    val d = dose ?: 0.0
    val drink = beverage ?: Extraction.estimatedBeverage(water ?: 0.0, d, espresso)
    val reading = tds?.let { Extraction.evaluate(it, drink, d, espresso) }

    BrewScreen(title = "Extraction", onBack = { nav.popBackStack() }) { padding ->
        CardList(padding) {
            item {
                BrewCard {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        PillChip("Filter", !espresso) { espresso = false }
                        PillChip("Espresso", espresso) { espresso = true }
                    }
                    Spacer(Modifier.height(10.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NumberField("Coffee (g)", dose, { dose = it }, Modifier.weight(1f), 0.0..150.0)
                        NumberField("TDS (%)", tds, { tds = it }, Modifier.weight(1f), 0.0..Extraction.MAX_TDS, decimals = 2)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NumberField(if (espresso) "Yield (g)" else "Water poured (g)", water, { water = it }, Modifier.weight(1f), 0.0..3000.0)
                        NumberField("Drink weighed (g)", beverage, { beverage = it }, Modifier.weight(1f), 0.0..3000.0)
                    }
                    if (beverage == null) {
                        Text("Drink estimated as ${fmt1(drink)} g" + if (espresso) " (the yield)." else " (water − 2 × coffee, the grounds hold it back).",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            item { ExtractionResult(reading, espresso) }
        }
    }
}

/** The reading with verdict, advice and the brewing control chart. */
@Composable
fun ExtractionResult(reading: Extraction.Reading?, espresso: Boolean) {
    BrewCard {
        if (reading == null) {
            Text("Enter a TDS reading from your refractometer to see the extraction yield.",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            val color = if (reading.verdict == Extraction.Verdict.IDEAL) GoodGreen else WarnOrange
            Text("${fmt1(reading.yield)} % extraction", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = color)
            Text("${reading.verdict.title}, ${reading.strength.title} (TDS ${fmt2(reading.tds)} %)", fontWeight = FontWeight.Medium)
            Text(reading.advice, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.height(10.dp))
        ExtractionChart(reading, espresso)
    }
}

/** TDS (up) against extraction yield (right), with the ideal box. */
@Composable
fun ExtractionChart(reading: Extraction.Reading?, espresso: Boolean) {
    val zone = Extraction.Zone.forMethod(espresso)
    val tdsRange = if (espresso) 6.0..14.0 else 0.9..1.7
    val eyRange = 14.0..26.0
    val grid = MaterialTheme.colorScheme.outlineVariant
    val accent = MaterialTheme.colorScheme.primary
    Column {
        Canvas(Modifier.fillMaxWidth().height(180.dp)) {
            fun x(ey: Double) = ((ey - eyRange.start) / (eyRange.endInclusive - eyRange.start)).toFloat().coerceIn(0f, 1f) * size.width
            fun y(t: Double) = (1 - ((t - tdsRange.start) / (tdsRange.endInclusive - tdsRange.start)).toFloat().coerceIn(0f, 1f)) * size.height
            drawRect(grid, style = androidx.compose.ui.graphics.drawscope.Stroke(1f))
            val left = x(zone.yield.start)
            val top = y(zone.tds.endInclusive)
            drawRect(GoodGreen.copy(alpha = 0.18f), Offset(left, top), Size(x(zone.yield.endInclusive) - left, y(zone.tds.start) - top))
            for (ey in 16..24 step 2) drawLine(grid, Offset(x(ey.toDouble()), 0f), Offset(x(ey.toDouble()), size.height))
            reading?.let { drawCircle(accent, 9f, Offset(x(it.yield), y(it.tds))) }
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp)) {
            Text("EY ${eyRange.start.toInt()} %", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
            Text("ideal ${zone.yield.start.toInt()}–${zone.yield.endInclusive.toInt()} % · TDS ${fmt2(zone.tds.start)}–${fmt2(zone.tds.endInclusive)} %",
                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
            Text("${eyRange.endInclusive.toInt()} %", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** TDS (and optionally the drink weight) on a saved brew, with its extraction. */
@Composable
fun BrewExtractionCard(brew: Brew, onChange: (tds: Double?, beverage: Double?) -> Unit) {
    val espresso = brew.recipe?.isEspresso == true
    val drink = brew.beverageWeight ?: Extraction.estimatedBeverage(brew.finalWeight, brew.dose, espresso)
    val reading = brew.tds?.let { Extraction.evaluate(it, drink, brew.dose, espresso) }
    SectionHeader("Extraction")
    Spacer(Modifier.height(8.dp))
    BrewCard {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NumberField("TDS (%)", brew.tds, { onChange(it?.takeIf { v -> v > 0 }, brew.beverageWeight) }, Modifier.weight(1f), 0.0..Extraction.MAX_TDS, decimals = 2)
            NumberField("Drink (g)", brew.beverageWeight, { onChange(brew.tds, it?.takeIf { v -> v > 0 }) }, Modifier.weight(1f), 0.0..3000.0)
        }
        if (reading != null) {
            val color = if (reading.verdict == Extraction.Verdict.IDEAL) GoodGreen else WarnOrange
            Text("${fmt1(reading.yield)} % extraction · ${reading.verdict.title}", fontWeight = FontWeight.SemiBold, color = color,
                modifier = Modifier.padding(top = 6.dp))
            Text(reading.advice, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            ExtractionChart(reading, espresso)
        } else {
            Text("Measured with a refractometer? Enter the TDS to see the extraction yield.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// MARK: - Water

@Composable
fun WaterCalculatorScreen(nav: NavHostController) {
    val container = LocalContainer.current
    var hardness by rememberSaveable { mutableStateOf<Double?>(68.0) }
    var alkalinity by rememberSaveable { mutableStateOf<Double?>(40.0) }
    var litres by rememberSaveable { mutableStateOf<Double?>(1.0) }
    var magnesium by rememberSaveable { mutableStateOf(1f) }
    var concentrates by rememberSaveable { mutableStateOf(false) }
    var name by rememberSaveable { mutableStateOf("SCA standard") }
    var saved by remember { mutableStateOf(false) }

    val recipe = WaterChemistry.Recipe(hardness ?: 0.0, alkalinity ?: 0.0, litres ?: 0.0, magnesium.toDouble())

    BrewScreen(title = "Water recipes", onBack = { nav.popBackStack() }) { padding ->
        CardList(padding) {
            item {
                BrewCard {
                    Text("Start from", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.height(6.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        WaterChemistry.presets.forEach { p ->
                            PillChip(p.name, name == p.name) { name = p.name; hardness = p.hardness; alkalinity = p.alkalinity; saved = false }
                        }
                    }
                    WaterChemistry.presets.firstOrNull { it.name == name }?.let {
                        Text(it.note, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
                    }
                }
            }
            item {
                BrewCard {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NumberField("Hardness GH (ppm)", hardness, { hardness = it; saved = false }, Modifier.weight(1f), 0.0..WaterChemistry.MAX_PPM, decimals = 0)
                        NumberField("Alkalinity KH (ppm)", alkalinity, { alkalinity = it; saved = false }, Modifier.weight(1f), 0.0..WaterChemistry.MAX_PPM, decimals = 0)
                    }
                    NumberField("Litres of water", litres, { litres = it }, Modifier.fillMaxWidth(), 0.0..WaterChemistry.MAX_LITRES, decimals = 2)
                    Spacer(Modifier.height(8.dp))
                    Text("Hardness from: ${(magnesium * 100).toInt()} % Epsom salt (brighter), ${100 - (magnesium * 100).toInt()} % calcium chloride (rounder)",
                        style = MaterialTheme.typography.bodySmall)
                    Slider(magnesium, { magnesium = (it * 10).toInt() / 10f }, valueRange = 0f..1f, steps = 9)
                    Text(WaterChemistry.character(hardness ?: 0.0, alkalinity ?: 0.0),
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            item {
                BrewCard {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        PillChip("Dry minerals", !concentrates) { concentrates = false }
                        PillChip("Concentrates", concentrates) { concentrates = true }
                    }
                    Spacer(Modifier.height(8.dp))
                    if (concentrates) {
                        ResultRow("Epsom concentrate", "${fmt1(recipe.hardnessConcentrateGrams)} g")
                        if (magnesium < 1f) ResultRow("Calcium chloride concentrate", "${fmt1(recipe.calciumConcentrateGrams)} g")
                        ResultRow("Baking soda concentrate", "${fmt1(recipe.bufferConcentrateGrams)} g")
                        ResultRow("Distilled water", "${fmt1(recipe.distilledGrams)} g")
                        Text("Concentrates: 2.46 g Epsom salt, 1.47 g calcium chloride or 1.68 g baking soda in 1 L of distilled water each (1000 ppm).",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } else {
                        ResultRow("Epsom salt (MgSO₄·7H₂O)", "${fmt2(recipe.epsomGrams)} g")
                        if (magnesium < 1f) ResultRow("Calcium chloride (CaCl₂·2H₂O)", "${fmt2(recipe.calciumChlorideGrams)} g")
                        ResultRow("Baking soda (NaHCO₃)", "${fmt2(recipe.bakingSodaGrams)} g")
                        Text("Dissolved in ${fmt1(litres ?: 0.0)} L of distilled or reverse-osmosis water. Small amounts: use a 0.01 g scale or concentrates.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            item {
                BrewCard {
                    androidx.compose.material3.OutlinedTextField(name, { name = it.take(80); saved = false }, label = { Text("Name") },
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(8.dp))
                    PrimaryButton(if (saved) "Saved as water profile" else "Save as water profile", enabled = !saved && name.isNotBlank()) {
                        container.repository.upsertEquipment(Equipment(
                            name = name.trim(), type = EquipmentType.WATER,
                            notes = WaterChemistry.summary(hardness ?: 0.0, alkalinity ?: 0.0),
                            waterHardness = hardness ?: 0.0, waterAlkalinity = alkalinity ?: 0.0,
                        ))
                        container.haptics.tap()
                        saved = true
                    }
                    Text("Water profiles show up in Gear and can be picked per brew on the Brew tab.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun ResultRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        Text(value, fontWeight = FontWeight.SemiBold)
    }
}

// MARK: - Grind converter

private data class ConvertibleGrinder(val name: String, val spec: GrinderSpec)

@Composable
fun GrindConverterScreen(nav: NavHostController) {
    val container = LocalContainer.current
    val data by container.repository.data.collectAsStateWithLifecycle()
    val grinders = remember(data.equipment) {
        val own = data.equipment.filter { it.type == EquipmentType.GRINDER }
            .map { ConvertibleGrinder(it.name, GrindConverter.calibrated(it.grinder, it.name)) }
        val presets = EquipmentPreset.all.filter { it.type == EquipmentType.GRINDER && it.grinder != null && own.none { o -> o.name == it.name } }
            .map { ConvertibleGrinder(it.name, GrindConverter.calibrated(it.grinder!!, it.name)) }
        (own + presets).filter { GrindConverter.canConvert(it.spec) }
    }
    var fromName by rememberSaveable { mutableStateOf(grinders.firstOrNull()?.name) }
    var toName by rememberSaveable { mutableStateOf(grinders.getOrNull(1)?.name) }
    val from = grinders.firstOrNull { it.name == fromName }
    val to = grinders.firstOrNull { it.name == toName }
    var value by rememberSaveable { mutableStateOf<Double?>(from?.spec?.defaultGrind) }
    val result = if (from != null && to != null && value != null) GrindConverter.convert(value!!, from.spec, to.spec) else null

    BrewScreen(title = "Grind converter", onBack = { nav.popBackStack() }) { padding ->
        CardList(padding) {
            if (grinders.size < 2) {
                item {
                    BrewCard {
                        Text("Add two calibrated grinders (a filter starting point and µm per step in the grinder's settings) to convert between them.",
                            style = MaterialTheme.typography.bodyMedium)
                    }
                }
                return@CardList
            }
            item { GrinderPicker("From", grinders, fromName) { fromName = it; value = grinders.firstOrNull { g -> g.name == it }?.spec?.defaultGrind } }
            item {
                BrewCard {
                    NumberField("Setting on ${from?.name ?: "grinder"}", value, { value = it }, Modifier.fillMaxWidth(), 0.0..10_000.0, decimals = 2)
                    from?.spec?.let { spec -> value?.let { v -> GrindConverter.microns(v, spec) } }?.let {
                        Text("≈ ${it.toInt()} µm on the shared scale", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            item { GrinderPicker("To", grinders, toName) { toName = it } }
            item {
                BrewCard {
                    if (result != null && to != null) {
                        Text(to.spec.format(result), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                        Text("on your ${to.name}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } else {
                        Text("Pick two grinders and a setting.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text("Burrs and zero points differ between grinders, so this is a starting point to taste from.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
                }
            }
        }
    }
}

@Composable
private fun GrinderPicker(title: String, grinders: List<ConvertibleGrinder>, selected: String?, onSelect: (String) -> Unit) {
    SectionHeader(title)
    Spacer(Modifier.height(8.dp))
    BrewCard {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            grinders.forEach { g -> PillChip(g.name, g.name == selected) { onSelect(g.name) } }
        }
    }
}

