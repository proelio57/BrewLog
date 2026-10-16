package com.brewlog.app.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.brewlog.app.LocalContainer
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.TasteFeedback
import com.brewlog.app.domain.fmt1
import com.brewlog.app.domain.formatDate
import com.brewlog.app.domain.mmss
import com.brewlog.app.ui.Routes
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.StarsLabel
import com.brewlog.app.ui.components.StatView
import com.brewlog.app.ui.components.icon
import com.brewlog.app.ui.theme.GoodGreen
import com.brewlog.app.ui.theme.WarnOrange

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun JournalScreen(nav: NavHostController) {
    val container = LocalContainer.current
    val data by container.repository.data.collectAsStateWithLifecycle()
    var search by rememberSaveable { mutableStateOf("") }
    var toDelete by remember { mutableStateOf<Brew?>(null) }
    val beans = data.beans.associateBy { it.id }
    val brews = data.brews.sortedByDescending { it.date }
    val filtered = if (search.isBlank()) brews else brews.filter { brew ->
        val bean = beans[brew.beanId]
        listOfNotNull(brew.recipeName, bean?.name, bean?.roaster, brew.notes).any { it.contains(search, ignoreCase = true) }
    }

    val context = androidx.compose.ui.platform.LocalContext.current
    var importResult by remember { mutableStateOf<String?>(null) }
    var showMenu by remember { mutableStateOf(false) }
    var showImportDialog by remember { mutableStateOf(false) }

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
        title = "Journal",
        actions = {
            Box {
                IconButton(onClick = { showMenu = true }) {
                    Icon(
                        Icons.Filled.MoreVert,
                        contentDescription = "More",
                    )
                }
                DropdownMenu(
                    expanded = showMenu,
                    onDismissRequest = { showMenu = false },
                ) {
                    DropdownMenuItem(
                        text = { Text("Import backup / recipes…") },
                        onClick = {
                            showMenu = false
                            showImportDialog = true
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("Export backup (JSON)") },
                        onClick = {
                            showMenu = false
                            val jsonStr = com.brewlog.app.data.DataImporter.exportBackup(container.repository)
                            val sendIntent = android.content.Intent().apply {
                                action = android.content.Intent.ACTION_SEND
                                putExtra(android.content.Intent.EXTRA_TEXT, jsonStr)
                                type = "application/json"
                            }
                            context.startActivity(android.content.Intent.createChooser(sendIntent, "Export BrewLog Backup"))
                        },
                    )
                }
            }
        },
    ) { padding ->
        if (brews.isEmpty()) {
            Box(Modifier.padding(padding)) {
                EmptyState(
                    title = "No brews yet",
                    message = "Every brew you finish is saved here with its pour curve, rating and suggestions.",
                    icon = Icons.Filled.Coffee,
                    action = {
                        Button(onClick = { showImportDialog = true }) {
                            Text("Import recipes or backup")
                        }
                    },
                )
            }
            return@BrewScreen
        }
        CardList(padding) {
            item {
                OutlinedTextField(search, { search = it.take(80) }, Modifier.fillMaxWidth(), singleLine = true,
                    placeholder = { Text("Recipe, bean, roaster, notes") }, leadingIcon = { Icon(Icons.Filled.Search, null) })
            }
            if (search.isBlank()) {
                item {
                    val rated = brews.filter { it.rating > 0 }
                    val weekAgo = System.currentTimeMillis() - 7 * 86_400_000L
                    BrewCard {
                        Row {
                            StatView("${brews.size}", "Brews")
                            StatView("${brews.count { it.date > weekAgo }}", "This week")
                            StatView(if (rated.isEmpty()) "–" else fmt1(rated.map { it.rating }.average()) + "★", "Avg rating")
                        }
                    }
                }
            }
            items(filtered, key = { it.id }) { brew ->
                Surface(
                    shape = RoundedCornerShape(20.dp),
                    color = MaterialTheme.colorScheme.surface,
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp))
                        .combinedClickable(onClick = { nav.navigate(Routes.brewDetail(brew.id)) }, onLongClick = { toDelete = brew }),
                ) {
                    BrewRow(brew, beans[brew.beanId]?.displayName)
                }
            }
            item {
                Text("Long-press a brew to delete it.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 4.dp))
            }
        }
    }

    toDelete?.let { brew ->
        AlertDialog(
            onDismissRequest = { toDelete = null },
            title = { Text("Delete this brew?") },
            text = { Text("${brew.recipeName} · ${formatDate(brew.date, withTime = true)}") },
            confirmButton = {
                TextButton(onClick = { container.repository.deleteBrew(brew.id); toDelete = null }) { Text("Delete", color = Color(0xFFFF3B30)) }
            },
            dismissButton = { TextButton(onClick = { toDelete = null }) { Text("Cancel") } },
        )
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
            confirmButton = {
                TextButton(onClick = { importResult = null }) { Text("OK") }
            },
        )
    }
}

@Composable
private fun BrewRow(brew: Brew, beanName: String?) {
    val tint = when {
        TasteFeedback.PERFECT in brew.feedback -> GoodGreen
        brew.feedback.isNotEmpty() -> WarnOrange
        else -> MaterialTheme.colorScheme.primary
    }
    val icon = brew.feedback.minByOrNull { it.ordinal }?.icon ?: Icons.Filled.Coffee
    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(46.dp).clip(RoundedCornerShape(12.dp)).background(tint.copy(alpha = 0.15f)), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = tint)
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(brew.recipeName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(beanName ?: "No beans", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            Text(
                listOfNotNull(formatDate(brew.date), brew.totalTime.mmss(), brew.grindDisplay.ifEmpty { null }).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            if (brew.rating > 0) StarsLabel(brew.rating)
            if (!brew.isReviewed) {
                Text("Review", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}
