@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)

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
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
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
import com.brewlog.app.domain.Bean
import com.brewlog.app.domain.InputLimits
import com.brewlog.app.domain.ProcessMethod
import com.brewlog.app.domain.RoastLevel
import com.brewlog.app.domain.clamped
import com.brewlog.app.domain.formatDate
import com.brewlog.app.domain.grams
import com.brewlog.app.domain.mmss
import com.brewlog.app.domain.sanitized
import com.brewlog.app.ui.Routes
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.PillChip
import com.brewlog.app.ui.components.SectionHeader
import com.brewlog.app.ui.components.StarsLabel
import com.brewlog.app.ui.theme.WarnOrange
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.size

@Composable
fun BeanListScreen(nav: NavHostController) {
    val data by LocalContainer.current.repository.data.collectAsStateWithLifecycle()
    val beans = data.beans.sortedByDescending { it.createdAt }
    BrewScreen(
        title = "Beans",
        actions = { IconButton(onClick = { nav.navigate(Routes.bean(Routes.NEW)) }) { Icon(Icons.Filled.Add, contentDescription = "Add beans") } },
    ) { padding ->
        if (beans.isEmpty()) {
            Box(Modifier.padding(padding)) {
                EmptyState("No beans yet", "Add the coffees you're brewing to track freshness, remaining weight and the best grind for each.",
                    Icons.Filled.Eco) { Button(onClick = { nav.navigate(Routes.bean(Routes.NEW)) }) { Text("Add beans") } }
            }
            return@BrewScreen
        }
        val active = beans.filter { !it.isArchived }
        val archived = beans.filter { it.isArchived }
        CardList(padding) {
            if (active.isNotEmpty()) {
                item { SectionHeader("On the shelf") }
                items(active, key = { it.id }) { bean -> BeanRow(bean, data.brews.count { it.beanId == bean.id }) { nav.navigate(Routes.bean(bean.id)) } }
            }
            if (archived.isNotEmpty()) {
                item { SectionHeader("Finished") }
                items(archived, key = { it.id }) { bean -> BeanRow(bean, data.brews.count { it.beanId == bean.id }) { nav.navigate(Routes.bean(bean.id)) } }
            }
        }
    }
}

@Composable
private fun BeanRow(bean: Bean, brewCount: Int, onClick: () -> Unit) {
    BrewCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            com.brewlog.app.ui.components.BeanThumbnail(bean.id, bean.roastLevel, size = 40.dp)
            Spacer(Modifier.width(12.dp))
            Text(bean.name, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(bean.roastLevel.displayName, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val origin = listOf(bean.roaster, bean.origin).filter { it.isNotEmpty() }.joinToString(" · ")
        if (origin.isNotEmpty()) Text(origin, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        val days = bean.daysOffRoast()
        Text(
            listOfNotNull(days?.let { "$it days" }, bean.remaining.grams() + " left", "$brewCount brews").joinToString(" · "),
            style = MaterialTheme.typography.bodySmall,
            color = if (days != null && (days < 4 || days > 45)) WarnOrange else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (bean.bagWeight > 0) {
            Spacer(Modifier.height(6.dp))
            LinearProgressIndicator(progress = { (bean.remaining / bean.bagWeight).coerceIn(0.0, 1.0).toFloat() }, modifier = Modifier.fillMaxWidth())
        }
    }
}

/** Create or edit beans. Edits stay local until Save. */
@Composable
fun BeanEditorScreen(nav: NavHostController, beanId: String) {
    val container = LocalContainer.current
    val data by container.repository.data.collectAsStateWithLifecycle()
    val existing = remember(beanId) { container.repository.data.value.beans.firstOrNull { it.id == beanId } }
    val isNew = existing == null
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var roaster by remember { mutableStateOf(existing?.roaster ?: "") }
    var origin by remember { mutableStateOf(existing?.origin ?: "") }
    var varietal by remember { mutableStateOf(existing?.varietal ?: "") }
    var process by remember { mutableStateOf(existing?.process ?: ProcessMethod.WASHED) }
    var roastLevel by remember { mutableStateOf(existing?.roastLevel ?: RoastLevel.LIGHT) }
    var roastDate by remember { mutableStateOf(existing?.roastDate) }
    var tastingNotes by remember { mutableStateOf(existing?.tastingNotes ?: "") }
    var notes by remember { mutableStateOf(existing?.notes ?: "") }
    var bagWeight by remember { mutableStateOf<Double?>(existing?.bagWeight ?: 250.0) }
    var remaining by remember { mutableStateOf<Double?>(existing?.remaining ?: 250.0) }
    var archived by remember { mutableStateOf(existing?.isArchived ?: false) }
    var showDatePicker by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    // The photo is kept here until Save (a new bean gets its id on save).
    var photo by remember { mutableStateOf(existing?.let { container.repository.beanPhoto(it.id) }) }
    var photoChanged by remember { mutableStateOf(false) }

    fun save() {
        val base = existing ?: Bean()
        val bean = base.copy(
            name = name.sanitized(InputLimits.MAX_NAME_LENGTH),
            roaster = roaster.sanitized(InputLimits.MAX_NAME_LENGTH),
            origin = origin.sanitized(InputLimits.MAX_NAME_LENGTH),
            varietal = varietal.sanitized(InputLimits.MAX_NAME_LENGTH),
            process = process,
            roastLevel = roastLevel,
            roastDate = roastDate?.coerceAtMost(System.currentTimeMillis()),
            tastingNotes = tastingNotes.sanitized(InputLimits.MAX_LONG_TEXT),
            notes = notes.sanitized(InputLimits.MAX_LONG_TEXT),
            bagWeight = (bagWeight ?: 0.0).clamped(0.0, InputLimits.MAX_BAG_WEIGHT),
            remaining = (remaining ?: 0.0).clamped(0.0, InputLimits.MAX_BAG_WEIGHT),
            isArchived = archived,
        )
        container.repository.upsertBean(bean)
        if (photoChanged) container.repository.setBeanPhoto(bean.id, photo)
        if (isNew) container.setup.beanId = bean.id
        nav.popBackStack()
    }

    BrewScreen(
        title = if (isNew) "New beans" else "Edit beans",
        onBack = { nav.popBackStack() },
        actions = {
            if (!isNew) IconButton(onClick = { nav.navigate(Routes.beanAdvice(beanId)) }) { Icon(Icons.Filled.AutoAwesome, contentDescription = "Ask Claude how to brew it") }
            if (!isNew) IconButton(onClick = { confirmDelete = true }) { Icon(Icons.Filled.Delete, contentDescription = "Delete") }
            TextButton(onClick = ::save, enabled = name.sanitized(InputLimits.MAX_NAME_LENGTH).isNotEmpty()) { Text("Save", fontWeight = FontWeight.SemiBold) }
        },
    ) { padding ->
        CardList(padding) {
            item {
                BeanPhotoCard(photo, roastLevel, onChange = { photo = it; photoChanged = true }) { scan ->
                    // Only empty fields are filled; the user checks them afterwards.
                    if (name.isBlank()) scan.name?.let { name = it }
                    if (roaster.isBlank()) scan.roaster?.let { roaster = it }
                    if (origin.isBlank()) scan.origin?.let { origin = it }
                    if (varietal.isBlank()) scan.varietal?.let { varietal = it }
                    if (tastingNotes.isBlank()) scan.tastingNotes?.let { tastingNotes = it }
                    scan.process?.let { process = it }
                    scan.roastLevel?.let { roastLevel = it }
                    scan.roastDate?.let { roastDate = it }
                    if (isNew) scan.bagWeight?.let { bagWeight = it; remaining = it }
                }
            }
            item {
                SectionHeader("Coffee")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    OutlinedTextField(name, { name = it.take(80) }, label = { Text("Name (e.g. Ethiopia Guji)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(roaster, { roaster = it.take(80) }, label = { Text("Roaster") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(origin, { origin = it.take(80) }, label = { Text("Origin") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(varietal, { varietal = it.take(80) }, label = { Text("Varietal") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(10.dp))
                    Text("Process", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.height(6.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        ProcessMethod.entries.forEach { p -> PillChip(p.displayName, process == p) { process = p } }
                    }
                }
            }
            item {
                SectionHeader("Roast")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        RoastLevel.entries.forEach { level -> PillChip(level.displayName, roastLevel == level) { roastLevel = level } }
                    }
                    Spacer(Modifier.height(10.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Roasted on", Modifier.weight(1f))
                        OutlinedButton(onClick = { showDatePicker = true }) { Text(roastDate?.let { formatDate(it) } ?: "Set date") }
                        if (roastDate != null) TextButton(onClick = { roastDate = null }) { Text("Clear") }
                    }
                    Text("Roast level and age are used in the analysis. Light roasts need hotter water, very fresh beans extract unevenly, and old beans taste flat.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            item {
                SectionHeader("Bag")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NumberField("Bag weight g", bagWeight, { bagWeight = it }, Modifier.weight(1f), 0.0..10_000.0, decimals = 0)
                        NumberField("Remaining g", remaining, { remaining = it }, Modifier.weight(1f), 0.0..10_000.0, decimals = 0)
                    }
                    Spacer(Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Finished / archived", Modifier.weight(1f))
                        Switch(checked = archived, onCheckedChange = { archived = it })
                    }
                }
            }
            item {
                SectionHeader("Notes")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    OutlinedTextField(tastingNotes, { tastingNotes = it.take(2000) }, label = { Text("Tasting notes from the roaster") }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(notes, { notes = it.take(2000) }, label = { Text("Your notes") }, minLines = 2, modifier = Modifier.fillMaxWidth())
                }
            }
            val brews = data.brews.filter { it.beanId == beanId }.sortedByDescending { it.date }
            if (!isNew && brews.isNotEmpty()) {
                item {
                    SectionHeader("Grind log")
                    Spacer(Modifier.height(8.dp))
                    BrewCard {
                        brews.forEachIndexed { index, brew ->
                            if (index > 0) HorizontalDivider(Modifier.padding(vertical = 6.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(brew.recipeName, fontWeight = FontWeight.SemiBold)
                                    Text("${formatDate(brew.date)} · ${brew.totalTime.mmss()}", style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Column(horizontalAlignment = Alignment.End) {
                                    Text(brew.grindDisplay.ifEmpty { "–" })
                                    if (brew.rating > 0) StarsLabel(brew.rating)
                                }
                            }
                        }
                        Text("Your brews of this bean, so you can see which grind worked best.", style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp))
                    }
                }
            }
        }
    }

    if (showDatePicker) {
        val state = rememberDatePickerState(initialSelectedDateMillis = roastDate ?: System.currentTimeMillis())
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = { roastDate = state.selectedDateMillis?.coerceAtMost(System.currentTimeMillis()); showDatePicker = false }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { showDatePicker = false }) { Text("Cancel") } },
        ) { DatePicker(state = state) }
    }
    if (confirmDelete && existing != null) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete these beans?") },
            text = { Text("Brews keep their data but lose the link to these beans.") },
            confirmButton = {
                TextButton(onClick = { container.repository.deleteBean(existing.id); confirmDelete = false; nav.popBackStack() }) {
                    Text("Delete", color = Color(0xFFFF3B30))
                }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
        )
    }
}

/**
 * Photo of the bag and label scan: system camera app or photo picker, so BrewLog needs no camera or storage
 * permission. The label text is read with Tesseract on the phone, nothing is uploaded.
 */
@Composable
private fun BeanPhotoCard(
    photo: ByteArray?,
    roast: RoastLevel,
    onChange: (ByteArray?) -> Unit,
    onScan: (com.brewlog.app.domain.LabelParser.Result) -> Unit,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var cameraUri by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf<String?>(null) }
    var scanPurpose by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }
    var scanning by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }

    fun use(uri: android.net.Uri) {
        val scan = scanPurpose
        scope.launch {
            if (!scan) {
                val bytes = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    com.brewlog.app.tools.BeanPhoto.bitmap(context, uri)?.let(com.brewlog.app.tools.BeanPhoto::jpeg)
                }
                if (bytes != null) onChange(bytes)
                return@launch
            }
            scanning = true
            message = null
            val bitmap = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                com.brewlog.app.tools.BeanPhoto.bitmap(context, uri, maxPixels = 2400)
            }
            if (bitmap == null) {
                scanning = false
                message = "The photo couldn't be opened."
                return@launch
            }
            val result = com.brewlog.app.tools.LabelScanner.scan(context, bitmap)
            // The bag photo doubles as the bean's photo when there is none yet.
            if (photo == null) onChange(kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { com.brewlog.app.tools.BeanPhoto.jpeg(bitmap) })
            scanning = false
            if (result.isEmpty) {
                message = "No details found. Try a sharper photo, straight on and in good light."
            } else {
                message = "Found " + result.foundFields.joinToString(", ") + ". Check the fields."
                onScan(result)
            }
        }
    }

    val pick = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia(),
    ) { uri -> if (uri != null) use(uri) }
    val take = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.TakePicture(),
    ) { ok -> cameraUri?.let { if (ok) use(android.net.Uri.parse(it)) } }

    fun camera(scan: Boolean) {
        scanPurpose = scan
        val dir = java.io.File(context.cacheDir, "photos").apply { mkdirs() }
        val file = java.io.File(dir, "bag.jpg")
        val uri = androidx.core.content.FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)
        cameraUri = uri.toString()
        runCatching { take.launch(uri) }.onFailure { message = "No camera app found. Choose a photo instead." }
    }

    fun library(scan: Boolean) {
        scanPurpose = scan
        pick.launch(androidx.activity.result.PickVisualMediaRequest(
            androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly))
    }

    BrewCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            com.brewlog.app.ui.components.BeanThumbnail(null, roast, size = 76.dp, photo = photo)
            Spacer(Modifier.width(14.dp))
            Column {
                Text("Photo", style = MaterialTheme.typography.labelLarge)
                Row {
                    TextButton(onClick = { camera(false) }) { Text("Take") }
                    TextButton(onClick = { library(false) }) { Text("Choose") }
                    if (photo != null) TextButton(onClick = { onChange(null) }) { Text("Remove", color = MaterialTheme.colorScheme.error) }
                }
                Text("Scan label", style = MaterialTheme.typography.labelLarge)
                if (scanning) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        androidx.compose.material3.CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                        Text("Reading label…", style = MaterialTheme.typography.bodySmall)
                    }
                } else {
                    Row {
                        TextButton(onClick = { camera(true) }) { Text("Photograph") }
                        TextButton(onClick = { library(true) }) { Text("From photo") }
                    }
                }
            }
        }
        message?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        Text("Scan label reads name, origin, process, varietal, roast date and weight from the bag. The text is recognized on this phone, nothing is uploaded.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
