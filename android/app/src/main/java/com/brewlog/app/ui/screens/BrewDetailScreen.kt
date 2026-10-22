@file:OptIn(ExperimentalLayoutApi::class)

package com.brewlog.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.brewlog.app.LocalContainer
import com.brewlog.app.analysis.BrewAnalysis
import com.brewlog.app.analysis.analyze
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.PressureSample
import com.brewlog.app.domain.StepKind
import com.brewlog.app.domain.TasteFeedback
import com.brewlog.app.domain.fmt1
import com.brewlog.app.domain.formatDate
import com.brewlog.app.domain.grams
import com.brewlog.app.domain.grams1
import com.brewlog.app.domain.mmss
import com.brewlog.app.domain.roundHalfAway
import com.brewlog.app.domain.sanitized
import com.brewlog.app.ui.Routes
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.BrewChart
import com.brewlog.app.ui.components.FilterIcon
import com.brewlog.app.ui.components.IconCircle
import com.brewlog.app.ui.components.MenuPickerRow
import com.brewlog.app.ui.components.MethodBadge
import com.brewlog.app.ui.components.PickerOption
import com.brewlog.app.ui.components.PillChip
import com.brewlog.app.ui.components.SectionHeader
import com.brewlog.app.ui.components.StarRating
import com.brewlog.app.ui.components.StatView
import com.brewlog.app.ui.components.color
import com.brewlog.app.ui.components.icon
import com.brewlog.app.ui.components.suggestionIcon
import com.brewlog.app.ui.switchTab
import com.brewlog.app.ui.theme.GoodGreen
import com.brewlog.app.ui.theme.WarnOrange
import kotlin.math.abs
import kotlin.math.max

/** Post-brew review (rating, taste, analysis, suggestions). Also the journal detail screen. */
@Composable
fun BrewDetailScreen(nav: NavHostController, brewId: String, isNew: Boolean) {
    val container = LocalContainer.current
    val repo = container.repository
    val data by repo.data.collectAsStateWithLifecycle()
    val brew = data.brews.firstOrNull { it.id == brewId }
    if (brew == null) {
        LaunchedEffect(Unit) { nav.popBackStack() }
        return
    }
    val samples = remember(brewId) { repo.samples(brewId) }
    val machineSamples = remember(brewId) { repo.machineSamples(brewId) }
    val bean = data.beans.firstOrNull { it.id == brew.beanId }
    val analysis = brew.analyze(data.brews, bean, samples, container.presets, machineSamples)

    // Remember the grind the analysis suggests, so the next brew of this bean starts there.
    LaunchedEffect(analysis?.suggestedGrind) {
        if (analysis != null && brew.suggestedGrind != analysis.suggestedGrind) {
            repo.updateBrew(brewId) { it.copy(suggestedGrind = analysis.suggestedGrind) }
        }
    }

    BrewScreen(
        title = if (isNew) "How was it?" else brew.recipeName,
        onBack = if (isNew) null else ({ nav.popBackStack() }),
        actions = {
            if (isNew) {
                TextButton(onClick = { nav.popBackStack() }) { Text("Save", fontWeight = FontWeight.SemiBold) }
            } else {
                TextButton(onClick = { nav.navigate(Routes.brewEditor(brew.id)) }) {
                    Text("Edit", fontWeight = FontWeight.SemiBold)
                }
            }
        },
    ) { padding ->
        CardList(padding) {
            item { SummaryCard(brew) }
            if (brew.usedScale && brew.recipe != null && samples.isNotEmpty()) {
                item {
                    SectionHeader("Pour curve")
                    Spacer(Modifier.height(8.dp))
                    BrewCard { BrewChart(samples, brew.recipe, height = 230.dp, showFlowRange = true, pressureSamples = machineSamples.map { PressureSample(it.t, it.p) }) }
                }
            }
            item { TasteCard(brew) }
            if (analysis != null) {
                item { SuggestionsCard(brew, analysis) }
                item { FindingsCard(analysis) }
                if (analysis.pours.isNotEmpty()) item { PoursCard(analysis) }
            }
            item { DetailsCard(nav, brew) }
            if (!isNew) {
                item {
                    TextButton(onClick = { brewAgain(container, brew); nav.switchTab(Routes.BREW) }, modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Filled.Refresh, null)
                        Spacer(Modifier.width(6.dp))
                        Text(if (brew.suggestedGrind != null && brew.suggestedGrind != brew.grindValue) "Brew again with suggestions" else "Brew again",
                            fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

private fun brewAgain(container: com.brewlog.app.AppContainer, brew: Brew) {
    val setup = container.setup
    val equipment = container.repository.data.value.equipment
    val recipe = brew.recipe
    if (recipe != null) {
        setup.select(container.allRecipes().firstOrNull { it.id == brew.recipeId } ?: recipe)
        setup.dose = brew.dose
        setup.waterTemp = brew.waterTemp
    }
    setup.beanId = brew.beanId
    brew.brewerId?.takeIf { id -> equipment.any { it.id == id } }?.let { setup.brewerId = it }
    brew.filterId?.takeIf { id -> equipment.any { it.id == id } }?.let { setup.filterId = it }
    brew.grinderId?.takeIf { id -> equipment.any { it.id == id } }?.let { setup.grinderId = it }
    setup.pinGrind(brew.suggestedGrind ?: brew.grindValue)
    setup.grindText = brew.grindSetting
}

@Composable
private fun SummaryCard(brew: Brew) {
    BrewCard {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(brew.recipeName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text(formatDate(brew.date, withTime = true), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            brew.recipe?.let { MethodBadge(it.method) }
        }
        Spacer(Modifier.height(12.dp))
        Row {
            StatView(brew.totalTime.mmss(), "Time", Icons.Filled.Timer)
            StatView(brew.finalWeight.grams(), "Water", Icons.Filled.WaterDrop)
            StatView("1:${fmt1(brew.ratio)}", "Ratio")
            StatView(brew.grindDisplay.ifEmpty { "–" }, "Grind", Icons.Filled.Tune)
        }
    }
}

@Composable
private fun TasteCard(brew: Brew) {
    val repo = LocalContainer.current.repository
    val haptics = LocalContainer.current.haptics
    SectionHeader("Taste")
    Spacer(Modifier.height(8.dp))
    BrewCard {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            StarRating(brew.rating) { rating -> repo.updateBrew(brew.id) { it.copy(rating = rating) }; haptics.tap() }
        }
        Spacer(Modifier.height(14.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            TasteFeedback.entries.forEach { item ->
                PillChip(item.title, item in brew.feedback, item.icon, if (item == TasteFeedback.PERFECT) GoodGreen else MaterialTheme.colorScheme.primary) {
                    repo.updateBrew(brew.id) { current -> toggleFeedback(current, item) }
                    haptics.tap()
                }
            }
        }
        if (brew.feedback.size == 1) {
            Spacer(Modifier.height(10.dp))
            Text(brew.feedback.first().subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun toggleFeedback(brew: Brew, item: TasteFeedback): Brew {
    var set = brew.feedback.toMutableSet()
    var rating = brew.rating
    if (item in set) {
        set.remove(item)
    } else if (item == TasteFeedback.PERFECT) {
        set = mutableSetOf(TasteFeedback.PERFECT)
        if (rating < 4) rating = 5
    } else {
        set.remove(TasteFeedback.PERFECT)
        set.add(item)
        // Sour vs bitter can coexist (uneven extraction). Weak vs strong can't.
        if (item == TasteFeedback.WEAK) set.remove(TasteFeedback.STRONG)
        if (item == TasteFeedback.STRONG) set.remove(TasteFeedback.WEAK)
    }
    return brew.copy(feedback = set, rating = rating)
}

@Composable
private fun SuggestionsCard(brew: Brew, analysis: BrewAnalysis) {
    var showAll by remember { mutableStateOf(false) }
    SectionHeader(if (brew.feedback.isEmpty()) "Analysis" else "What to try next", analysis.lean.title)
    Spacer(Modifier.height(8.dp))
    BrewCard {
        Text(analysis.headline, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        if (brew.feedback.isEmpty()) {
            Spacer(Modifier.height(6.dp))
            Text("Choose how it tasted above. BrewLog compares your taste with the pour data and suggests what to change.",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val visible = if (showAll) analysis.suggestions else analysis.suggestions.take(3)
        visible.forEachIndexed { index, suggestion ->
            if (index > 0) HorizontalDivider(Modifier.padding(vertical = 10.dp)) else Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.Top) {
                IconCircle(suggestionIcon(suggestion.key), MaterialTheme.colorScheme.primary, size = 36,
                    background = MaterialTheme.colorScheme.primary.copy(alpha = if (index == 0) 0.2f else 0.1f))
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(suggestion.title, fontWeight = FontWeight.SemiBold)
                    Text(suggestion.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    suggestion.evidence.forEach { evidence ->
                        Row(Modifier.padding(top = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.AutoMirrored.Filled.ShowChart, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.primary)
                            Spacer(Modifier.width(4.dp))
                            Text(evidence, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
        }
        if (analysis.suggestions.size > 3) {
            TextButton(onClick = { showAll = !showAll }) {
                Text(if (showAll) "Show less" else "Show ${analysis.suggestions.size - 3} more", fontWeight = FontWeight.SemiBold)
            }
        }
        val next = analysis.suggestedGrind
        val spec = brew.grinderSpec
        if (next != null && spec != null && brew.feedback.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.AutoAwesome, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(6.dp))
                Text("Next time BrewLog will pre-fill ${spec.format(next)} for ${if (brew.beanId == null) "this recipe" else "this bean"}.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}

@Composable
private fun FindingsCard(analysis: BrewAnalysis) {
    var showAll by remember { mutableStateOf(false) }
    SectionHeader("Brew data")
    Spacer(Modifier.height(8.dp))
    BrewCard {
        val visible = if (showAll) analysis.findings else analysis.findings.take(5)
        visible.forEach { finding ->
            Row(Modifier.padding(vertical = 5.dp), verticalAlignment = Alignment.Top) {
                Icon(finding.level.icon, null, tint = finding.level.color, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(10.dp))
                Column {
                    Text(finding.title, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium)
                    Text(finding.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (analysis.findings.size > 5) {
            TextButton(onClick = { showAll = !showAll }) {
                Text(if (showAll) "Show less" else "Show all ${analysis.findings.size}", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun PoursCard(analysis: BrewAnalysis) {
    SectionHeader("Pours")
    Spacer(Modifier.height(8.dp))
    BrewCard {
        Row {
            listOf("#" to 0.4f, "Plan" to 1.4f, "Actual" to 1.4f, "Flow" to 0.6f).forEach { (title, weight) ->
                Text(title, Modifier.weight(weight), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        analysis.pours.forEach { pour ->
            Row(Modifier.padding(top = 8.dp)) {
                Text(if (pour.step.kind == StepKind.BLOOM) "B" else "${pour.number}", Modifier.weight(0.4f), fontWeight = FontWeight.Bold)
                Text("${pour.step.time.mmss()} → ${pour.target.toInt()} g", Modifier.weight(1.4f))
                if (pour.detected) {
                    val off = abs(pour.weightDelta ?: 0.0) > max(3.0, pour.target * 0.04)
                    Text("${(pour.actualStart ?: 0.0).mmss()} → ${roundHalfAway(pour.reached ?: 0.0).toInt()} g", Modifier.weight(1.4f),
                        color = if (off) WarnOrange else MaterialTheme.colorScheme.onSurface)
                } else {
                    Text("not detected", Modifier.weight(1.4f), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(pour.averageFlow?.let { fmt1(it) } ?: "–", Modifier.weight(0.6f))
            }
        }
    }
}

@Composable
private fun DetailsCard(nav: NavHostController, brew: Brew) {
    val container = LocalContainer.current
    val repo = container.repository
    val data by repo.data.collectAsStateWithLifecycle()
    val beanOptions = data.beans.filter { !it.isArchived || it.id == brew.beanId }.map { PickerOption(it.id, it.displayName) }
    var notes by remember(brew.id) { mutableStateOf(brew.notes) }
    SectionHeader("Details")
    Spacer(Modifier.height(8.dp))
    BrewCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) {
                MenuPickerRow("Beans", Icons.Filled.Eco, beanOptions, brew.beanId) { repo.assignBean(brew.id, it) }
            }
            IconButton(onClick = { nav.navigate(Routes.bean(Routes.NEW)) }) {
                Icon(Icons.Filled.AddCircle, contentDescription = "Add beans", tint = MaterialTheme.colorScheme.primary)
            }
        }
        HorizontalDivider(Modifier.padding(vertical = 8.dp))
        val spec = brew.grinderSpec
        if (spec != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Build, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(8.dp))
                Text(brew.grinderName, Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
                NumberField("Grind", brew.grindValue, { value -> repo.updateBrew(brew.id) { it.copy(grindValue = value) } },
                    Modifier.width(120.dp), decimals = if (spec.step < 1) 2 else 0)
            }
        } else {
            OutlinedTextField(brew.grindSetting, { value -> repo.updateBrew(brew.id) { it.copy(grindSetting = value.take(80)) } },
                label = { Text("Grind") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        }
        HorizontalDivider(Modifier.padding(vertical = 8.dp))
        DetailRow("Brewer", brew.brewerName, Icons.Filled.Coffee)
        DetailRow("Filter", brew.filterName, FilterIcon)
        DetailRow("Dose", brew.dose.grams1(), Icons.Filled.WaterDrop)
        DetailRow("Water temp", "${brew.waterTemp.toInt()} °C", Icons.Filled.Thermostat)
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            value = notes,
            onValueChange = { value ->
                notes = value.take(2_000)
                repo.updateBrew(brew.id) { it.copy(notes = notes.sanitized(2_000)) }
            },
            label = { Text("Notes: aroma, flavours, what you changed…") },
            minLines = 3,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun DetailRow(title: String, value: String, icon: androidx.compose.ui.graphics.vector.ImageVector) {
    Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(8.dp))
        Text(title, Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value.ifEmpty { "–" }, color = if (value.isEmpty()) Color.Gray else MaterialTheme.colorScheme.onSurface)
    }
}
